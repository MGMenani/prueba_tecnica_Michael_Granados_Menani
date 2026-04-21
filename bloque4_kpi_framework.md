# Bloque 4 — Framework de KPIs: Programa de Mejora de Productividad de Tiendas

## North Star Metric

**GMV por Metro Cuadrado (GMV/m²) — semanal por tienda**

### Justificación
El GMV/m² normaliza el desempeño de ventas por el tamaño de cada tienda, permitiendo comparar de forma justa una tienda EXPRESS de 400 m² con un HIPERMERCADO de 8,000 m². Es la métrica que mejor captura si una tienda está **extrayendo valor de su espacio físico**, que es el activo más costoso de una cadena de retail. Cuando este número sube, es señal de que la combinación de surtido, exhibición, precio y experiencia está funcionando. Si baja, concentra la atención del equipo directivo en el lugar correcto.

---

## Tabla de KPIs

### KPI 1 — GMV por Metro Cuadrado ⭐ North Star

**Definición** | Ingresos brutos de ventas generados por cada metro cuadrado de la tienda 
**Fórmula** | `GMV_semana / size_sqm` 
**Frecuencia**  Semanal 
**Fuente de datos** | `transactions` + `stores` 
**Target sugerido** | Por encima del P25 de GMV/m² del formato correspondiente (benchmark interno) 
**¿Cómo detectas si el dato está mal?** | Si GMV/m² cae >50% vs. semana anterior sin justificación → revisar si `size_sqm` cambió o si hay fallo en el reporte de ventas de esa tienda 

---

### KPI 2 — Comp Sales Growth % (Crecimiento de Ventas Comparables)

| **Definición** | Crecimiento porcentual del GMV vs. el mismo período del año anterior, solo para tiendas con 13+ meses de operación |
| **Fórmula** | `(GMV_periodo_actual - GMV_periodo_anterior) / GMV_periodo_anterior × 100` |
| **Frecuencia** | Mensual y trimestral |
| **Fuente de datos** | `transactions` + `stores` (filtro por `opening_date`) |
| **Target sugerido** | ≥ 3% mensual (benchmark de la industria de retail centroamericano) |
| **¿Cómo detectas si el dato está mal?** | Si todas las tiendas de un país muestran el mismo crecimiento exacto → posible error de JOIN o filtro de fecha incorrecto |

---

### KPI 3 — Ticket Promedio por Transacción

| **Definición** | Monto promedio gastado por cliente en cada visita a la tienda |
| **Fórmula** | `SUM(total_amount) / COUNT(DISTINCT transaction_id)` |
| **Frecuencia** | Diaria (vista operativa), semanal (tendencia) |
| **Fuente de datos** | `transactions` (excluyendo total_amount = 0 y status = RETURNED) |
| **Target sugerido** | Varía por formato: HIPERMERCADO > $80, SUPERMERCADO > $50, EXPRESS > $25, DESCUENTO > $20 |
| **¿Cómo detectas si el dato está mal?** | Ticket promedio < $1 o > $5,000 → verificar si hay transacciones con monto 0 no excluidas o registros duplicados |

---

### KPI 4 — Tasa de Retención de Clientes Leales (Leading Indicator)

| **Definición** | Porcentaje de clientes con tarjeta de lealtad que realizaron al menos una transacción en el mes actual vs. el mes anterior. Es un **leading indicator**: predice el GMV futuro antes de que se materialice |
| **Fórmula** | `Clientes_activos_mes_actual ∩ Clientes_activos_mes_anterior / Clientes_activos_mes_anterior × 100` |
| **Frecuencia** | Mensual |
| **Fuente de datos** | `transactions` (WHERE loyalty_card = TRUE AND customer_id IS NOT NULL) |
| **Target sugerido** | ≥ 40% retención mes a mes. Caída de >5 puntos porcentuales vs. mes anterior = alerta |
| **¿Cómo detectas si el dato está mal?** | Retención del 100% → revisar si el filtro de customer_id está colapsando IDs. Retención del 0% → posible fallo en el campo loyalty_card del período |

---

### KPI 5 — GMROI por Proveedor (KPI Compuesto)


| **Definición** | Retorno sobre la inversión en costo de mercancía por proveedor. **KPI compuesto**: combina margen bruto (KPI financiero) y costo total (KPI de abastecimiento) |
| **Fórmula** | `(GMV - Costo_total) / Costo_total` donde `Costo_total = SUM(cost × quantity)` |
| **Frecuencia** | Trimestral |
| **Fuente de datos** | `transaction_items` + `products` + `vendors` |
| **Target sugerido** | GMROI ≥ 1.5. GMROI < 1 = el proveedor genera menos margen que lo que cuesta → revisión de contrato |
| **¿Cómo detectas si el dato está mal?** | GMROI = 0 para un proveedor activo → verificar que el campo `cost` en `products` esté poblado. GMROI > 10 → revisar si hay ítems con costo registrado en $0 |

---

### KPI 6 — Tasa de Quiebre de Stock

| **Definición** | Porcentaje de combinaciones tienda-ítem que presentaron 3 o más días consecutivos sin ventas en períodos donde históricamente sí vendían |
| **Fórmula** | `Combinaciones_con_gap≥3días / Total_combinaciones_tienda_ítem_activas × 100` |
| **Frecuencia** | Semanal |
| **Fuente de datos** | `transactions` + `transaction_items` (análisis de gaps consecutivos) |
| **Target sugerido** | < 2% de combinaciones activas con quiebre. >5% = alerta crítica de abastecimiento |
| **¿Cómo detectas si el dato está mal?** | Si la tasa sube de 2% a 80% en un día → posible fallo en la ingesta de datos de esa tienda, no un quiebre real |

---

### KPI 7 — Penetración de Tarjeta de Lealtad

| **Definición** | Porcentaje de transacciones realizadas con tarjeta de lealtad sobre el total |
| **Fórmula** | `COUNT(tx donde loyalty_card = TRUE) / COUNT(total_tx) × 100` |
| **Frecuencia** | Semanal |
| **Fuente de datos** | `transactions` |
| **Target sugerido** | ≥ 45% a nivel cadena. Por formato: HIPERMERCADO ≥ 55%, EXPRESS ≥ 30% |
| **¿Cómo detectas si el dato está mal?** | Penetración = 0% para una tienda → verificar si el sistema POS de esa tienda reportó correctamente el campo `loyalty_card`. Penetración = 100% → revisar si el campo tiene valor por defecto |

---

### KPI 8 — Margen Bruto % por Categoría

| **Definición** | Porcentaje de margen bruto sobre el GMV por categoría de producto. **KPI compuesto**: combina GMV (resultado de ventas) y costo (eficiencia de abastecimiento) |
| **Fórmula** | `(SUM(unit_price × qty) - SUM(cost × qty)) / SUM(unit_price × qty) × 100` |
| **Frecuencia** | Mensual |
| **Fuente de datos** | `transaction_items` + `products` |
| **Target sugerido** | Varía por categoría: Alimentos 18–25%, Electrónica 12–18%, Ropa 35–45%, Hogar 28–35% |
| **¿Cómo detectas si el dato está mal?** | Margen negativo en una categoría entera → verificar si el campo `cost` fue actualizado correctamente con el último precio de compra. Margen > 80% → posible error en el costo registrado |

---

## Resumen del Framework

| # | KPI | Dimensión | Tipo | Frecuencia |
| 1 | GMV/m² ⭐ | Productividad de tienda | Resultado | Semanal |
| 2 | Comp Sales Growth % | Productividad de tienda | Resultado | Mensual |
| 3 | Ticket Promedio | Experiencia del cliente | Resultado | Diario |
| 4 | Tasa de Retención de Lealtad | Experiencia del cliente | **Leading** | Mensual |
| 5 | GMROI por Proveedor | Desempeño de proveedor | **Compuesto** | Trimestral |
| 6 | Tasa de Quiebre de Stock | Productividad de tienda | **Leading** | Semanal |
| 7 | Penetración de Lealtad | Experiencia del cliente | Resultado | Semanal |
| 8 | Margen Bruto % | Desempeño de proveedor | **Compuesto** | Mensual |
