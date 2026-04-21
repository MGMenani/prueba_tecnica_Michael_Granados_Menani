# Bloque 2 — Modelado de Datos + Diseño de Pipeline

## A. Modelo Dimensional — Star Schema en BigQuery

### Diagrama (texto — ver `bloque2_modelo.pdf` para el diagrama visual)

```
                        ┌──────────────────┐
                        │   dim_date       │
                        │──────────────────│
                        │ date_key (PK)    │
                        │ full_date        │
                        │ day, month, year │
                        │ quarter          │
                        │ week_of_year     │
                        │ is_weekend       │
                        └────────┬─────────┘
                                 │
┌──────────────┐    ┌────────────▼──────────────────────────────┐    ┌──────────────────┐
│  dim_store   │    │            fact_transactions               │    │  dim_product     │
│──────────────│    │────────────────────────────────────────────│    │──────────────────│
│ store_key(PK)│◄───│ transaction_key  (PK surrogate)            │───►│ product_key (PK) │
│ store_id     │    │ date_key         (FK → dim_date)           │    │ item_id          │
│ store_name   │    │ store_key        (FK → dim_store)          │    │ item_name        │
│ country      │    │ customer_key     (FK → dim_customer)       │    │ brand            │
│ city         │    │ product_key      (FK → dim_product)        │    │ category         │
│ format       │    │ promo_key        (FK → dim_promotion)      │    │ department       │
│ size_sqm     │    │                                            │    │ cost             │
│ opening_date │    │ quantity         (medida)                  │    │ vendor_key (FK)  │
│ region       │    │ unit_price       (medida)                  │    └──────────────────┘
└──────────────┘    │ line_amount      (medida: price*qty)       │
                    │ total_amount     (medida, nivel tx)        │    ┌──────────────────┐
┌──────────────┐    │ payment_method                             │    │  dim_vendor      │
│ dim_customer │    │ was_on_promo                               │    │──────────────────│
│──────────────│    │ is_identified_customer                     │    │ vendor_key (PK)  │
│customer_key  │◄───│ status                                     │    │ vendor_id        │
│customer_id   │    │ is_excluded (flag auditoría)               │    │ vendor_name      │
│is_identified │    └────────────────────────────────────────────┘    │ country          │
│first_tx_date │                        │                             │ tier             │
│cohort_month  │             ┌──────────▼──────────┐                  │ is_shared_catalog│
└──────────────┘             │   dim_promotion     │                  └──────────────────┘
                             │─────────────────────│
                             │ promo_key (PK)       │
                             │ store_id             │
                             │ promo_name           │
                             │ variant (CTR/TRTMNT) │
                             │ promo_type           │
                             │ start_date           │
                             │ end_date             │
                             └─────────────────────┘
```

### Grain de la tabla de hechos
La tabla `fact_transactions` tiene **grain a nivel de ítem de transacción** (una fila = un producto en una transacción). Esto permite:
- Analizar GMV por categoría y proveedor sin joins adicionales.
- Calcular GMROI directamente.
- Filtrar por `was_on_promo` al nivel correcto.

---

## B. Decisiones de Diseño — Justificaciones

### Decisión 1: Grain a nivel de ítem, no de transacción

**Problema:** Hay dos niveles de datos: la transacción (cabecera) y los ítems (detalle).

**Decisión:** El fact vive al nivel de ítem. Los campos de cabecera (`total_amount`, `payment_method`) se repiten en cada ítem de la transacción.

**Justificación:** La mayoría de los KPIs del negocio requieren análisis por categoría, proveedor y producto. Si el grain fuera la transacción, necesitaríamos un join costoso con `transaction_items` en cada query. Con grain por ítem, el costo de redundancia de datos es bajo comparado con la ganancia en rendimiento y simplicidad de las queries.

---

### Decisión 2: Cómo modelar el 60% de transacciones sin `customer_id`

**Problema:** 104,632 transacciones (60%) no tienen cliente identificado. Un NULL en la FK rompe integridad referencial y complica los análisis de cohortes.

**Decisión:**
- Se crea un registro especial en `dim_customer`: `customer_key = -1`, `customer_id = 'CUST_00000'`, `is_identified = FALSE`.
- Toda transacción sin cliente apunta a este registro surrogate.
- Se agrega la columna `is_identified_customer` en el fact para filtrar fácilmente.

**Justificación:** Este es el patrón estándar de dimensiones de tipo "unknown member" en diseño dimensional (Kimball). Permite:
- Hacer COUNT(*) sin excluir nulos.
- Filtrar `is_identified = TRUE` para análisis de lealtad.
- Nunca tener NULLs en FKs, lo que rompe las herramientas de BI.

---

### Decisión 3: Flag `is_excluded` en el fact en lugar de borrar registros

**Problema:** La auditoría identificó registros a excluir: 3 transacciones con monto $0, 17 transacciones de Tienda 37 pre-apertura, y transacciones de Tiendas 8 y 37 durante el A/B test.

**Decisión:** Se agrega una columna `is_excluded BOOLEAN` en el fact con la razón de exclusión en una columna `exclusion_reason STRING`. Los registros no se borran.

**Justificación:**
- **Auditabilidad:** Los registros originales quedan disponibles para investigación.
- **Flexibilidad:** Diferentes análisis pueden necesitar diferentes criterios de exclusión.
- **Reversibilidad:** Si la auditoría concluye que una exclusión fue incorrecta, no se perdió el dato.
- Las views de presentación (`rpt_*`) filtran `WHERE is_excluded = FALSE` por defecto.

---

### Decisión 4: Tabla de hechos particionada por `transaction_date`

**Decisión:** Particionar `fact_transactions` por `DATE(transaction_date)` en BigQuery.

**Justificación:** El 95% de las queries filtran por rango de fechas (semana actual, último trimestre, comparación YoY). Sin particionamiento, cada query escanea toda la tabla. Con 542K filas hoy y crecimiento continuo, el costo y latencia escalarían linealmente. El particionamiento reduce el escaneo al período relevante.

---

### Decisión 5: `total_amount` vs. `line_amount` como métrica oficial de GMV

**Decisión:** Se incluyen ambas métricas en el fact:
- `line_amount = unit_price * quantity` (desde transaction_items)
- `total_amount` (desde transactions, con descuentos aplicados)

**Justificación:** Como detectamos en la auditoría, difieren en ~$32K (~1,745 transacciones). El negocio debe definir cuál es el GMV "oficial". Mientras se valida, se incluyen las dos y se documenta la diferencia. Las views de reporte usan `total_amount` por defecto hasta que el negocio defina la métrica oficial.

---

## C. Diseño del Pipeline ETL/ELT

### Flujo general

```
[Tiendas / POS] ──(hasta 2h retraso)──► [Landing Zone / GCS]
                                              │
                                    ┌─────────▼──────────┐
                                    │  Carga incremental  │
                                    │  (cada 30 min)      │
                                    │  MERGE por tx_id    │
                                    └─────────┬──────────┘
                                              │
                                    ┌─────────▼──────────┐
                                    │  Staging / Raw BQ   │
                                    │  (datos crudos,     │
                                    │   con load_ts)      │
                                    └─────────┬──────────┘
                                              │
                                    ┌─────────▼──────────┐
                                    │  Transform + Tests  │
                                    │  (dbt / Dataform)   │
                                    └─────────┬──────────┘
                                              │
                                    ┌─────────▼──────────┐
                                    │  fact_transactions  │
                                    │  + dim_*            │
                                    │  (BigQuery)         │
                                    └─────────┬──────────┘
                                              │
                                    ┌─────────▼──────────┐
                                    │  Dashboard / PBI    │
                                    │  (refresh diario)   │
                                    └────────────────────┘
```

### Preguntas del pipeline

**¿Cómo manejarías que las tiendas reportan ventas con hasta 2 horas de retraso?**
El pipeline corre cada **30 minutos**, pero al calcular métricas del día en curso se excluyen las últimas 3 horas (`WHERE load_timestamp < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 3 HOUR)`). Esto crea un "ventana de gracia" que absorbe el retraso de 2 horas con margen. Los dashboards muestran un banner de "datos actualizados hasta HH:MM".

**¿Cómo detectarías que una tienda dejó de enviar datos?**
Se implementa un monitor de "expected vs. received": cada tienda tiene un volumen histórico promedio de transacciones por hora. Si en 4 horas consecutivas una tienda registra 0 transacciones (y no es de madrugada), se dispara una alerta en el sistema de monitoreo (Cloud Monitoring / PagerDuty). La query de detección corre cada hora.

**¿Cómo harías cargas incrementales sin duplicar transacciones?**
Se usa un patrón `MERGE` (upsert) en BigQuery:
```sql
MERGE fact_transactions AS target
USING staging_new_transactions AS source
  ON target.transaction_id = source.transaction_id
     AND target.item_id = source.item_id
WHEN MATCHED THEN UPDATE SET ...    -- actualiza si el registro cambió
WHEN NOT MATCHED THEN INSERT ...    -- inserta solo registros nuevos
```
El staging siempre incluye una columna `load_timestamp` para auditoría.

**¿Con qué frecuencia correría el pipeline si el dashboard necesita refresh diario?**
El pipeline ETL corre cada **30 minutos** para capturar las transacciones con retraso. El refresh del dashboard de Power BI se programa a las **6:00 AM** (antes de que los gerentes regionales inicien su jornada), con un refresh adicional a las **12:00 PM** para capturar transacciones de la mañana.

---

## D. Gobernanza

**¿Cómo protegerías `customer_id` para cumplir con políticas de privacidad?**
- El `customer_id` real se almacena en una tabla separada con acceso restringido (`pii.customer_mapping`), protegida por IAM (solo el equipo de CRM tiene acceso).
- En `fact_transactions` y `dim_customer` se almacena únicamente un **hash irreversible** (`SHA-256`) del `customer_id`.
- Los analistas trabajan con el hash — pueden hacer análisis de cohortes y retención sin ver el ID real.
- Cualquier análisis que requiera el ID real necesita aprobación y acceso temporal auditado.

**¿Quién debería ser el data owner de la tabla de transacciones?**
- **Data Owner:** Gerencia de Operaciones Comerciales / Retail (quien genera y es responsable del proceso de negocio).
- **Data Steward:** Equipo de Data Engineering (responsable de la calidad técnica, pipeline y accesos).
- **Consumers:** Analítica, Finanzas, Marketing (acceso de lectura según necesidad).

**Si dos reportes muestran GMV diferente para la misma tienda y el mismo día, ¿cuál sería tu proceso?**
1. Identificar las **definiciones de métrica** usadas en cada reporte (¿`total_amount` vs. `line_amount`? ¿incluye RETURNED?).
2. Revisar los **filtros aplicados** (¿se excluyen las transacciones de auditoría?).
3. Trazar la **lineage** de cada reporte hasta la tabla fuente en BigQuery.
4. Si las fuentes son las mismas pero los números difieren → revisar si hay **joins duplicados** o agregaciones incorrectas.
5. Documentar la causa raíz y establecer la **métrica oficial** en el catálogo de datos para evitar futuros conflictos.
6. Publicar la resolución en el canal de datos del equipo.
