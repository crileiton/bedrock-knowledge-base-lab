# Resultados del laboratorio: KB vectorial vs Managed KB

Este documento recoge las pruebas que se ejecutaron sobre las dos Knowledge Bases del laboratorio, con las respuestas obtenidas, los tiempos medidos y las conclusiones.

- **Fecha de ejecución:** 2026-11-08 (UTC)
- **Datos crudos:** [`resultados/pruebas.json`](../resultados/pruebas.json), generado con [`scripts/pruebas.py`](../scripts/pruebas.py)
- **Repeticiones:** cada caso se ejecutó 3 veces por KB; se reporta la mediana y las tres latencias
- **Corpus:** los 3 documentos ficticios de [`docs-fuente/`](../docs-fuente), idénticos en ambas KB

## 1. Las dos alternativas evaluadas

| | KB vectorial (customer-managed) | Managed KB |
|---|---|---|
| Tipo de KB | `VECTOR` | `MANAGED` |
| Región | `us-east-2` | `us-east-1` (no disponible en `us-east-2`) |
| Vector store | Amazon S3 Vectors (índice `float32`, 1024 dims, coseno) | Administrado por Bedrock |
| Embeddings | Amazon Titan Text Embeddings V2 | Modelo administrado |
| Chunking | Tamaño fijo: 300 tokens, 20 % de solapamiento | Automático, consciente de la estructura |
| Re-ranking | No | Re-ranker administrado |
| Generación de respuestas | `RetrieveAndGenerate` con Claude Haiku 4.5 (`us.anthropic.claude-haiku-4-5-20251001-v1:0`) | `AgenticRetrieveStream` con modelos administrados |
| Recursos de Terraform propios | Vector bucket, índice, rol con 4 permisos, KB, data source | Rol con 2 permisos, KB, data source |

## 2. Ingesta

Tiempos leídos del historial de *ingestion jobs* (`ListIngestionJobs`): diferencia entre el inicio y la última actualización del job.

| Ingesta | KB vectorial | Managed KB |
|---|---|---|
| **Inicial** (3 documentos nuevos) | **4,9 s** | **152,2 s** |
| **Incremental** (sin cambios) | **0,6 s** | **61,6 s** |
| Documentos escaneados | 3 | 3 |
| Archivos `.metadata.json` leídos | 3 | 3 |
| Fallidos | 0 | 0 |

**Lectura:**
- Las dos KB hacen **sincronización incremental**: en la segunda ingesta escanearon los 3 documentos, detectaron que no habían cambiado y no reindexaron nada.
- La Managed KB es unas **30 veces más lenta** en la ingesta inicial. Hace *parsing* multimodal y un chunking por estructura, en vez de solo cortar texto cada 300 tokens. Incluso sin cambios, su sincronización tarda alrededor de un minuto.
- Las dos leyeron los `.metadata.json` y los dejaron disponibles para filtrar.

## 3. Pruebas de consulta

### P1. Recuperación de un dato puntual (`Retrieve`)

> ¿Cuántos días tengo para devolver un café y qué condiciones debe cumplir?

| # | KB vectorial | Score | Managed KB | Score |
|---|---|---|---|---|
| 1 | política de devoluciones (desde *"**sin abrir** y con la válvula…"*) | 0,737 | política de devoluciones (desde *"## Devoluciones – Se aceptan devoluciones dentro de los **10 días**…"*) | 0,472 |
| 2 | política de devoluciones (inicio del documento) | 0,731 | política de devoluciones (inicio del documento) | 0,388 |
| 3 | ficha técnica de procesos (fermentación/secado) | 0,656 | FAQ de suscripción | 0,209 |

| Latencia | KB vectorial | Managed KB |
|---|---|---|
| Mediana | 0,49 s | 0,58 s |
| Ejecuciones | 1,09 / 0,49 / 0,38 s | 1,15 / 0,56 / 0,58 s |

**Lectura:**
- **Chunking:** en la KB vectorial, el dato clave ("10 días calendario") queda en la frontera entre dos chunks de tamaño fijo, y ningún chunk empieza con la sección completa. La Managed KB cortó por la sección `## Devoluciones` y el primer chunk trae la respuesta entera.
- **Scores:** en la KB vectorial, los tres resultados quedan muy juntos (0,74 / 0,73 / 0,66), aunque el tercero es irrelevante. En la Managed KB, el re-ranker los separa mucho más (0,47 / 0,39 / 0,21). Los scores **no se pueden comparar entre las dos KB**, porque usan escalas distintas.
- **Primera llamada:** en las dos KB, la primera ejecución fue cerca de 2 veces más lenta (efecto de arranque en frío).

### P2. Respuesta generada con citas

> ¿Cuántos días tengo para devolver un café y qué condiciones debe cumplir?

**KB vectorial, `RetrieveAndGenerate`** (mediana 2,00 s; ejecuciones 1,99 / 2,14 / 2,00 s). Documentos citados: `politica-envios-devoluciones.md`.

> Tienes 10 días calendario desde la entrega para devolver un café. El café debe cumplir las siguientes condiciones: estar sin abrir y tener la válvula desgasificadora intacta. La excepción es si el producto llegó dañado, en cuyo caso debes enviar una foto al correo de soporte dentro de las primeras 48 horas y la cooperativa cubre el costo de reenvío. Ten en cuenta que los cafés de la línea "Microlote Reserva" no admiten devoluciones excepto por daño en el transporte, ya que se tuestan bajo pedido.

**Managed KB, `AgenticRetrieveStream`** (mediana 5,41 s; ejecuciones 5,41 / 5,24 / 6,10 s). Documentos citados: `politica-envios-devoluciones.md`. Pasos del agente: recuperación especulativa → planificación.

> Tienes **10 días calendario** desde la entrega para devolver un café.
>
> Para que la devolución sea válida, el producto debe cumplir estas condiciones:
>
> - El café debe estar **sin abrir**, con la **válvula desgasificadora intacta**.
> - Si el producto llegó **dañado**, debes enviar una foto al correo de soporte dentro de las primeras **48 horas**; en ese caso la cooperativa cubre el costo de reenvío.
> - Los reembolsos se procesan en un plazo máximo de **7 días hábiles**, devueltos al mismo medio de pago utilizado en la compra.
>
> **Excepción importante**: los cafés de la línea **"Microlote Reserva"** no admiten devoluciones, salvo que el daño se haya producido durante el transporte, ya que estos cafés se tuestan bajo pedido.

**Lectura:** para una pregunta que se responde con un solo documento, las dos respuestas son correctas. La Managed KB agrega el plazo de reembolso, pero tarda unas **2,7 veces más**.

### P3 y P4. Filtro por metadatos (`Retrieve` con `categoria`)

> ¿Cuántos días dura el secado del proceso honey?

La respuesta está en `ficha-tecnica-procesos.md`, cuyo metadato es `categoria = produccion`.

| Caso | Filtro | KB vectorial | Managed KB |
|---|---|---|---|
| P3 | `atencion-cliente` (excluye la respuesta) | 3 chunks de envíos y suscripción (0,574 / 0,552 / 0,536) | 2 chunks de envíos y suscripción (0,448 / 0,236) |
| P4 | `produccion` (incluye la respuesta) | ficha técnica: chunk con *"Proceso honey… 18 y 22 días"* (0,779) y el inicio del documento (0,587) | ficha técnica: inicio del documento (0,350) |
| Latencia (mediana) | P3 / P4 | 0,49 s / 0,41 s | 0,53 s / 0,55 s |

**Lectura:**
- En las dos KB, **el filtro se aplica antes de la búsqueda**: con `atencion-cliente`, el documento correcto ni siquiera se compara. Por eso los metadatos sirven como control de acceso por documento.
- Pedimos 3 resultados. La KB vectorial devolvió 3 en P3 y 2 en P4, porque con el filtro `produccion` solo existen 2 chunks. La Managed KB devolvió 2 y 1: **descarta los resultados de baja relevancia** en vez de rellenar hasta K.
- En P4, la KB vectorial devolvió primero el chunk exacto. La Managed KB devolvió el documento desde su inicio; con un chunking por estructura, ese chunk contiene la sección completa.

### P5. Pregunta multi-hop (requiere tres documentos)

> Quiero el café que se hace con proceso honey pero en suscripción anual. ¿Cuánto pagaría, qué recibo de regalo y puedo devolverlo si no me gusta?

Para responder bien hay que encadenar tres hechos que están en documentos distintos:

1. Proceso honey → línea "Microlote Reserva" (ficha técnica).
2. "Microlote Reserva" → **no admite devoluciones** salvo daño en el transporte (política de devoluciones).
3. Plan anual → 920.000 COP con molino de regalo (FAQ de suscripción).

**KB vectorial, `RetrieveAndGenerate`** (mediana 2,66 s; ejecuciones 2,65 / 2,68 / 2,66 s). Citó `faq-suscripcion.md` y `politica-envios-devoluciones.md`. **No citó la ficha técnica.**

> El plan de suscripción anual cuesta 920.000 COP e incluye un molino manual de regalo. Respecto a las devoluciones, se aceptan dentro de 10 días calendario después de la entrega, siempre que el café esté sin abrir y con la válvula desgasificadora intacta. Sin embargo, la política de devoluciones no especifica si aplica para casos de "no me gusta" o solo para productos dañados. Nota: Los search results no especifican si la suscripción "Taza Mensual" permite elegir específicamente el proceso honey. Solo indican que puedes elegir el tipo de molienda, pero no el método de procesamiento del café.

**Managed KB, `AgenticRetrieveStream`** (mediana 10,87 s; ejecuciones 11,68 / 10,02 / 10,87 s). Citó los tres documentos: `faq-suscripcion.md`, `ficha-tecnica-procesos.md` y `politica-envios-devoluciones.md`.

> ## Precio y regalo del plan anual
>
> - El plan anual de la suscripción "Taza Mensual" cuesta **920.000 COP** y, al suscribirte, recibes de regalo un **molino manual**.
> - Cada mes, además, recibes **dos bolsas de 340 g** de cafés diferentes, una tarjeta de cata con notas sensoriales y una receta de preparación sugerida.
>
> ## Sobre el café de proceso honey
>
> El café elaborado con proceso honey corresponde a la línea **"Microlote Reserva"** de la Cooperativa Cafetera Nubes Altas. En este proceso se conserva entre el **40% y el 60%** del mucílago de la cereza, y el secado dura entre **18 y 22 días** en camas africanas.
>
> ## ¿Puedo devolverlo si no me gusta?
>
> Aquí está el punto importante: **los cafés de la línea "Microlote Reserva" (que es donde está el café honey) no admiten devoluciones**, salvo que el producto haya llegado dañado durante el transporte, ya que se tuestan bajo pedido.
>
> Para otros cafés que no sean de esa línea, la política general sí permite devoluciones dentro de los **10 días calendario** siguientes a la entrega, siempre que el café esté sin abrir y con la válvula desgasificadora intacta. […]
>
> | Aspecto | Detalle |
> |---|---|
> | Precio plan anual | 920.000 COP |
> | Regalo incluido | Molino manual |
> | Café honey | Línea "Microlote Reserva" |
> | ¿Admite devolución? | **No**, salvo daño comprobado en el transporte (se tuesta bajo pedido) |

*(Respuesta completa en `resultados/pruebas.json`.)*

**Lectura: es la diferencia más importante del laboratorio.**
- La KB vectorial hizo **una sola búsqueda** con la pregunta completa. No recuperó la ficha técnica, así que no pudo relacionar "honey" con "Microlote Reserva", y respondió que **sí se aceptan devoluciones en 10 días**. Esa respuesta es **incorrecta** para este producto. Al menos reconoció que le faltaba información.
- La Managed KB encadenó los tres documentos y llegó a la conclusión correcta: **no se puede devolver**. Cuesta **4 veces más latencia** (10,9 s frente a 2,7 s).

### P6. Pregunta fuera del alcance de los documentos

> ¿Tienen tienda física en Medellín y cuál es su horario de atención?

**KB vectorial, `RetrieveAndGenerate`** (mediana 1,68 s; ejecuciones 1,90 / 1,58 / 1,68 s). Sin citas.

> No encontré información en los documentos disponibles sobre si la Cooperativa Cafetera Nubes Altas tiene una tienda física en Medellín o cuál sería su horario de atención. Los documentos que tengo acceso contienen información sobre procesos de beneficio del café y políticas de envíos y devoluciones, pero no incluyen detalles sobre ubicaciones físicas o horarios de atención.

**Managed KB, `AgenticRetrieveStream`** (mediana 7,31 s; ejecuciones 6,35 / 7,31 / 7,61 s). Pasos del agente: recuperación especulativa → planificación → **nueva recuperación** → planificación.

> No encontré información en la base de conocimiento sobre una tienda física en Medellín ni sobre horarios de atención al público de la Cooperativa Cafetera Nubes Altas. Los documentos disponibles solo cubren temas de envíos, devoluciones, procesos de beneficio del café y la suscripción "Taza Mensual", pero no mencionan puntos de venta físicos ni horarios de atención. Si necesitas esa información, te recomiendo contactar directamente a la cooperativa por sus canales de atención al cliente.

**Lectura:**
- Ninguna de las dos **alucinó**: las dos dijeron que no tenían la información (*grounding*).
- La traza muestra el ciclo agéntico. Como la primera búsqueda no alcanzó, el agente **planificó una segunda búsqueda** antes de rendirse. Esa iteración extra explica la latencia.

## 4. Resumen de latencias (mediana de 3 ejecuciones)

| Caso | API (vectorial / managed) | KB vectorial | Managed KB | Relación |
|---|---|---|---|---|
| P1 Recuperación | Retrieve / Retrieve | 0,49 s | 0,58 s | 1,2× |
| P2 Respuesta simple | RetrieveAndGenerate / AgenticRetrieveStream | 2,00 s | 5,41 s | 2,7× |
| P3 Filtro que excluye | Retrieve / Retrieve | 0,49 s | 0,53 s | 1,1× |
| P4 Filtro que incluye | Retrieve / Retrieve | 0,41 s | 0,55 s | 1,3× |
| P5 Multi-hop | RetrieveAndGenerate / AgenticRetrieveStream | 2,66 s | 10,87 s | 4,1× |
| P6 Fuera de alcance | RetrieveAndGenerate / AgenticRetrieveStream | 1,68 s | 7,31 s | 4,4× |

Las latencias se midieron desde una sola ubicación y con 3 repeticiones. Sirven para comparar órdenes de magnitud, no como benchmark.

## 5. Calidad de las respuestas

| Caso | KB vectorial | Managed KB |
|---|---|---|
| P2 Respuesta simple | ✅ Correcta | ✅ Correcta y más completa |
| P5 Multi-hop | ❌ Incorrecta: dice que se puede devolver | ✅ Correcta: encadena los 3 documentos |
| P6 Fuera de alcance | ✅ No inventa | ✅ No inventa; reintenta la búsqueda antes |

## 6. Incidencias durante el laboratorio

| Incidencia | Causa | Solución |
|---|---|---|
| Ingesta falló con `429 Too many requests` | La cuenta tenía cuota **0** de inferencia en Bedrock (Service Quotas) | Desplegar en una cuenta con cuota. Con cuota 0, el error aparece aunque IAM esté bien |
| Ingesta falló con `403 Your account is currently being verified` | Cuenta en verificación | Esperar a que terminara la verificación (menos de 2 h) |
| La Managed KB no se podía crear en `us-east-2` | Servicio disponible solo en algunas regiones | Segundo provider con `alias` en `us-east-1` y un bucket propio en esa región (el bucket debe estar en la misma región que la KB) |
| `Provider produced inconsistent result after apply` en el data source administrado | Bedrock completa valores por defecto del conector (`filterConfiguration`, `aclEnabled`, extracción de imágenes) | Declarar esos valores explícitamente y `terraform untaint` |
| `vectorSearchConfiguration is not supported for managed knowledge bases` | La Managed KB usa otra clave | `managedSearchConfiguration` |
| `RetrieveAndGenerate`: *operation not supported for managed knowledge bases* | La Managed KB no expone esa API | `AgenticRetrieveStream` |

## 7. Conclusiones

1. **Para preguntas simples, las dos alternativas responden bien.** La KB vectorial es entre 2 y 3 veces más rápida y la ingesta es casi instantánea.
2. **Para preguntas que cruzan documentos, la recuperación agéntica cambia el resultado.** Con una sola búsqueda, la KB vectorial dio una respuesta incorrecta y verosímil (P5), que es el peor tipo de error en un asistente. La Managed KB planificó, buscó y encadenó los hechos.
3. **El chunking importa.** El de tamaño fijo cortó la sección de devoluciones por la mitad (P1). El chunking por estructura la conservó entera. En la KB vectorial, esa decisión **no se puede cambiar** sin recrear el data source.
4. **El re-ranking mejora la señal.** La Managed KB separa mejor lo relevante de lo irrelevante y no rellena con resultados malos (P1, P3, P4). En la KB vectorial, `Retrieve` siempre devuelve K resultados y los scores quedan muy juntos.
5. **El filtrado por metadatos funciona igual en las dos** y es la base del control de acceso por documento (P3, P4).
6. **La Managed KB elimina infraestructura**: no hay vector store, índice ni dimensiones, el rol solo lee S3 y no se elige modelo de embeddings. A cambio, la ingesta es más lenta, las consultas agénticas tardan más, hay menos regiones y se pierde `RetrieveAndGenerate`.

### Cuándo elegir cada una

| Situación | Elección |
|---|---|
| RAG sin administrar infraestructura, preguntas complejas o multi-hop, conectores como SharePoint, Confluence o Drive | **Managed KB** |
| Control del vector store, del chunking, del modelo y de las dimensiones de embeddings | **KB vectorial** |
| Latencia baja en respuestas generadas | **KB vectorial** |
| Región donde la Managed KB no está disponible | **KB vectorial** |
| Necesitas `RetrieveAndGenerate` con sesiones y plantillas de prompt propias | **KB vectorial** |
| Costo mínimo con poco tráfico | Las dos son baratas con poco volumen. S3 Vectors cobra por almacenamiento y consultas; la Managed KB, por almacenamiento y por llamada de recuperación |
