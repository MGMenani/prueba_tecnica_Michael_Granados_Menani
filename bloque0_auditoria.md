# Análisis de los datasets
## products
filas: 200
columnas: 7

## store_promotions
filas: 42
columnas: 6 

## stores
filas: 40
columnas: 8 

## transaction_items
filas: 542,015
columnas: 6

## transactions
filas: 174,880
columnas: 8
customers vacíos: 104,632
% customers vacíos: 59.83%

## vendors
filas: 30
columnas: 5

# Preguntas
## Completitud: 
Transacciones sin customer_id: 104,632 (59.83%)
True Loyalty Card: 70,248 (40.17%)
False Loyalty Card: 104,632 (59.83%)
Las transacciones sin Customer ID coinciden al 100% con Loyalty Card en False

Las validaciones se realizaron en PBI, creando visualizaciones de tabla y medidas calculadas
Se crearon las medidas:
- MSR_TRANS_COUNT = COUNT(transactions[transaction_id])
- MST_TRANS_BLANK_COUNT = COUNTBLANK(transactions[customer_id]) 
- MST_TRANS_BLANK_CUSTOMER_% = [MSR_TRANS_BLANK_COUNT]/[MSR_TRANS_COUNT]

Acción: Corregir. En las celdas vacías de customer_id colocar un identificador para saber que no tiene un 
customer identificado. Para seguir con el mismo formato se podría colocar 'CUST_00000'. Se realizó una búsqueda rápida para 
verificar que no exista dicho código hasta el momento.

## Consistencia:
La validación se realizó en PBI. Se creó una visualización de tabla donde se comparó el monto total de la tabla 'transactions' y
el monto total calculado de la tabla 'transaction_item'. Además, se validó que la cantidad de transaction_id distintos fuera el 
mismo. Los resultados del monto total fue el siguiente:
- transactions: 48,719,262.24
- transaction_item: 48,751,364.86
- transaction_id distintos: 174,880

Los montos de las transacciones no coinciden y se puede deber porque en la tabla transactions está el precio con descuento, pero en la de transaction_item indica cuándo tiene descuento, pero el monto unitario es el monto real sin descuento.

Acción: Marcar como alerta. Se debe verificar si realmente es porque estos items estuvieron realmente en oferta.

Afectaciones: Son 1,745 transacciones afectadas (aprox. 1% del total)

## Unicidad:
En la tabla transactions no hay transaction_id duplicados. Por otro lado, en la tabla transaction_item sí hay duplicados, pero esto es normal, ya que los items asociados a cada transacción aparecen en una fila distinta.

Esto se comprobó en PBI al ver que la cantidad de transaction_id distintos en la tabla transaction es la misma que la cantidad de transacciones (filas) en la tabla. Además, se pudo realizar una relación entre tablas 1-* por lo que confirma la unicidad.

Acción: Ninguna

## Validez
TX_00036043, TX_00065737 y TX_00108161:
- total_amount y unit_price en 0
- no está en promo

No hay negativos.

Se colocó una tabla en PBI donde se filtraron las transacciones con total_amount = 0 y se verificó en la tabla transaction_item para verificar unit_price y was_on_promo

Acción: Excluir y marcar como alerta. Se debe rastrear por qué está pasando esto, mientras tanto, se tratan como outliers y se excluyen del modelo.

## Integridad referencial
Las 40 tiendas de stores coinciden con las 40 tiendas presentes en transactions
En vendors existen 30 vendors, pero en products hay un vendor VND_31 el cual no está en tabla vendors y tiene productos de alimentos y cuidado personal.

Esto se verificó usando las relaciones entre tablas en PBI y verificando cuándo se generaba un null

Acción: Marcar como alerta y corregir. Se marca para rastrear cuál puede ser este vendor desconocido, pero se puede trabajar con estos datos y colocarlo en el reporte como Vendor desconocido.

## Frescura
Todas las tiendas, menos la 37 tienen registros de ventas cada uno de los 547 días de base de datos.
Tienda 37 no vendió en los 547 días registrados en la tabla, ya que solo vendió en 412 días.
Esta tienda no tuvo transacciones desde enero 2024 porque abrió el 6/1/2024, pero la primera transacción registrada fue el 5/15/2024, por lo que hay inconsistencia.

Esto se verificó en PBI realizando un conteo de días distintos donde se registraron ventas por cada tienda.

Acción: Marcar como alerta. Con respecto a los días no registrados se entiende que es porque a enero la tienda no había abierto. Sin embargo, se debe revisar la fecha de las primeras transacciones.

## Integridad temporal
Tienda 37: abrió el 6/1/2024, pero la primera transacción registrada fue el 5/15/2024
Se creó la siguiente medida:
MSR_TRANS_VS_OPEN_DT = 
VAR _trans_dt = SELECTEDVALUE(transactions[transaction_date])
VAR _open_dt = SELECTEDVALUE(stores[opening_date])
RETURN
IF(_trans_dt >= _open_dt, "Bien", "Mal")

De esta manera se obtuvo que solamente la tienda 37 tiene transacciones anteriores a la fecha de apertura

Acción: Marcar como alerta y excluir. Se debe verificar si la fecha de apertura y las transacciones está correcta. Se excluye la tienda mientras se valida la información.

Afectaciones: tabla transactions tiene 17 filas con la tienda 37 antes de la fecha de apertura. Esto corresponde a un monto de 13,422.65

## A/B Test
Hay inconsistencia en la tienda 8 y 37

Se verificó con una visualización de tabla en PBI donde se colocaron todas las tiendas y un conteo de distintos valores en la columna variant de la tabla store_promotions

Acción: Se marcan como alerta y se excluyen estos casos para verificar el origen del problema. Sin embargo, se van a excluir mientras se validan.

Afectaciones: del 1 de septiembre al 12 de octubre hay 649 transacciones para la tienda 8 y 124 para la tienda 37 para un monto de 183,157.94 y 36,274 correspondientemente.


