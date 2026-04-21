# Prueba Técnica — Data Analyst
## Michael Granados Menani

Cadena de retail multiformato · Centroamérica · 18 meses de historia · 6 datasets CSV.

---

## Estructura del Repositorio

```
prueba_tecnica_Michael_Granados_Menani/
│
├── README.md                        ← Este archivo
├── bloque0_auditoria.md             ← Auditoría de calidad de datos
├── bloque1_queries.sql              ← 6 queries SQL (BigQuery SQL)
├── bloque2_decisiones.md            ← Star Schema + ETL + Gobernanza
├── bloque2_modelo.pdf               ← Diagrama visual del Star Schema (draw.io)
├── bloque4_kpi_framework.md         ← Framework de 8 KPIs con North Star
├── bloque5_dashboard.pbix           ← Dashboard operativo en Power BI
└── bloque5_presentacion_EN.pdf      ← Presentación ejecutiva en inglés (5 slides)
```

---

## Datasets utilizados

| Archivo | Filas | Descripción |
|---|---|---|
| `transactions.csv` | 174,880 | Transacciones de ventas |
| `transaction_items.csv` | 542,015 | Ítems por transacción |
| `stores.csv` | 40 | Tiendas (5 países, 4 formatos) |
| `products.csv` | 200 | Catálogo de productos |
| `vendors.csv` | 30 | Proveedores |
| `store_promotions.csv` | 42 | Experimentos A/B por tienda |

---

## Cómo ejecutar las queries SQL (Bloque 1)

Las queries están escritas en **BigQuery SQL estándar**.

1. Cargar los 6 archivos CSV en un dataset de BigQuery (ej. `prueba_tecnica`).
2. Abrir `bloque1_queries.sql` en el editor de BigQuery.
3. Ejecutar cada query individualmente. cada una tiene su sección delimitada con comentarios.

**Requisitos:** Acceso a Google BigQuery. Las queries no requieren librerías externas.

**Exclusiones aplicadas en todas las queries:**
- Transacciones con `total_amount = 0` (3 registros).
- Tienda 37 excluida por transacciones previas a su fecha de apertura.
- Tiendas 8 y 37 excluidas del análisis A/B (asignadas a ambos grupos simultáneamente).

---

## Cómo ver el dashboard (Bloque 5)

1. Abrir 'bloque5_dashboard.pbix' con Power BI Desktop (versión mayo 2025 o superior).
2. Al abrir, actualizar la fuente de datos apuntando a la carpeta local donde están los CSV.
3. El dashboard no requiere conexión a internet una vez cargados los datos.

---

## Uso de Inteligencia Artificial

Esta prueba técnica fue desarrollada con asistencia de Code Puppy (agente de IA interno de Walmart) y ChatGPT como herramientas de apoyo.

### ¿Qué generó la IA?

| Entregable | Aportación de la IA | Modificación propia |
| `bloque1_queries.sql` | Estructura base de las CTEs y sugerencias de funciones de ventana | Lógica de negocio, exclusiones de auditoría, validación de resultados |
| `bloque2_decisiones.md` | Formato y organización del documento | Todas las decisiones de diseño son propias, basadas en el análisis de los datos |
| `bloque4_kpi_framework.md` | Formato de tabla y estructura del documento | Selección de KPIs, targets y justificaciones son propias |
| `README.md` | Generado con asistencia de IA | Revisado y ajustado |

### Prompts principales utilizados

- IA: ChatGPT Prompt: cuántos días hay entre enero 2024 – junio 2025 Resultado: hay 547 días entre enero 2024 y junio 2025 (incluyendo ambos periodos completos). Motivo de la búsqueda: Para buscar indicios de tiendas que no hayan vendido algún día, ya que se realizó el conteo de días distintos con ventas reportadas. Las tiendas que no tuvieran 547 días habría que revisarlas.
- Ayúdame a identificar las discrepancias entre total_amount en transactions y la suma de unit_price × quantity en transaction_items
- Genera las 6 queries SQL del bloque 1 con BigQuery SQL, usando las exclusiones de la auditoría

### ¿Qué validé manualmente?

- Todos los hallazgos del Bloque 0 fueron validados en Power BI con medidas DAX propias.
- Las queries SQL fueron parcialmente revisadas para verificar la lógica de negocio.
- Los KPIs del Bloque 4 fueron seleccionados con base en mi criterio analítico y conocimiento del negocio retail.
- El dashboard de Power BI fue construido enteramente de forma manual.

---

## Decisiones Clave de la Auditoría

Ver `bloque0_auditoria.md` para el detalle completo. Resumen:

- **Excluir:** 3 transacciones con monto $0, 17 transacciones de Tienda 37 pre-apertura.
- **Alerta activa:** VND_31 sin registro en `vendors`, discrepancia de $32K entre tablas.
- **A/B Test:** Excluir Tiendas 8 y 37 del análisis experimental.
- **Corregir:** Asignar `CUST_00000` a los 104,632 registros sin `customer_id`.
