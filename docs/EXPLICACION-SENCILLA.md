# Amazon Bedrock Knowledge Bases explicado de forma sencilla

Este documento cuenta todo el laboratorio con ejemplos de la vida diaria, sin palabras técnicas. Cuando aparece una palabra técnica, va entre paréntesis, para que puedas relacionar la idea con el nombre real.

Si quieres la versión técnica, lee el [README](../README.md) y los [resultados](RESULTADOS.md).

---

## 1. El problema: un robot muy listo que no conoce tu tienda

Imagina un **robot que sabe muchísimo**. Leyó millones de libros, sabe historia, matemáticas, recetas y chistes (es un **modelo de lenguaje**, como Claude).

Pero tiene un problema: **no sabe nada de tu tienda**. Si le preguntas:

> "¿Cuántos días tengo para devolver un café en la Cooperativa Nubes Altas?"

el robot no lo sabe, porque esa información nunca estuvo en sus libros. Y a veces, cuando no sabe algo, **se lo inventa** con mucha seguridad (eso se llama **alucinar**).

**La solución:** darle al robot una **biblioteca con los papeles de tu tienda** y enseñarle a buscar ahí antes de responder. Esa biblioteca es una **Knowledge Base** (base de conocimiento).

A la idea de "primero busca en la biblioteca y después responde" se le llama **RAG**: *buscar* (Retrieval), *sumar lo encontrado a la pregunta* (Augmented) y *responder* (Generation).

---

## 2. Los papeles de la tienda

Para el laboratorio inventamos una tienda: la **Cooperativa Cafetera Nubes Altas**. No existe. La inventamos **a propósito**: si el robot responde con datos de esta tienda, sabemos con seguridad que los sacó de nuestra biblioteca y no de su memoria.

Escribimos 3 documentos:

| Documento | De qué habla |
|---|---|
| Política de envíos y devoluciones | Cuánto cuesta enviar, cuántos días hay para devolver un café |
| Ficha técnica de procesos | Cómo se hace el café: lavado, honey, natural |
| Preguntas frecuentes de la suscripción | Precios de los planes mensual, trimestral y anual |

A cada documento le pegamos una **etiqueta de color**: "atención al cliente" o "producción" (son los **metadatos**, en los archivos `.metadata.json`). Más adelante verás para qué sirven.

---

## 3. Cómo se arma una biblioteca para robots

Una biblioteca para robots no funciona como una normal. Hay que hacer cuatro cosas.

### Paso 1: guardar los papeles en una caja

Primero metemos los documentos en una **caja fuerte en la nube** (un **bucket de Amazon S3**). Le pusimos candado:
- nadie de afuera puede verla (**bloqueo de acceso público**);
- lo de adentro está escrito en clave (**cifrado**);
- solo se puede hablar con ella por un teléfono seguro (**solo HTTPS/TLS**).

### Paso 2: cortar los papeles en tarjetas

El robot no lee documentos enteros de golpe. Es como estudiar con **tarjetas de memoria**: cortamos cada documento en pedacitos (cada pedacito es un **chunk**).

Hay dos formas de cortar:
- **Con regla:** cada tarjeta tiene exactamente el mismo tamaño, unas 300 palabras (**chunking de tamaño fijo**). Es rápido, pero a veces corta una idea por la mitad, como cortar una frase en dos tarjetas distintas.
- **Por capítulos:** cada tarjeta es una sección completa, por ejemplo "Devoluciones" (**chunking por estructura**). Las ideas quedan enteras.

Para que una idea cortada no se pierda, las tarjetas hechas con regla **repiten un poquito del final de la anterior**, como cuando un libro empieza el capítulo recordando lo último que pasó (**solapamiento**; aquí usamos el 20 %).

### Paso 3: darle a cada tarjeta una "dirección en el mapa de las ideas"

Esta es la parte mágica. Imagina un **mapa gigante** donde cada idea tiene un lugar:
- "devolver un café" y "reembolso" quedan **cerquita**, porque significan algo parecido;
- "devolver un café" y "secar granos al sol" quedan **lejos**.

A cada tarjeta le calculamos su **dirección en ese mapa**. La dirección es una lista de 1024 números (un **vector** o **embedding**). Quien calcula las direcciones es otro robot especializado (el **modelo de embeddings**, aquí **Titan Text Embeddings V2**).

> Regla importante: el mapa y las direcciones tienen que usar **la misma cantidad de números**. Si el mapa espera direcciones de 1024 números y le das una de 512, no cabe. Eso es lo que significa que **las dimensiones tienen que coincidir**.

### Paso 4: guardar las tarjetas en un estante ordenado por ideas

Las tarjetas con su dirección se guardan en un **estante especial ordenado por significado** (la **base de datos vectorial** o **vector store**; aquí, **Amazon S3 Vectors**).

Cuando alguien pregunta algo, el estante calcula la dirección de la pregunta y busca **las tarjetas que viven más cerca** en el mapa. Para medir qué tan cerca están dos ideas usamos la **distancia coseno**: mira si apuntan hacia el mismo lado.

### Todo esto junto se llama "ingesta"

Meter los papeles, cortarlos, calcular las direcciones y guardarlas en el estante es la **ingesta**. Hay que repetirla **cada vez que cambian los documentos**. Y la biblioteca es inteligente: la segunda vez **solo procesa lo que cambió** (**sincronización incremental**).

---

## 4. El permiso del bibliotecario

El que hace todo ese trabajo es Amazon Bedrock, que actúa como **bibliotecario**. Pero no puede entrar a tus cosas así como así: necesita un **carné con permisos** (un **rol de IAM**).

Su carné dice exactamente qué puede hacer, y nada más (**mínimo privilegio**):
- ✅ leer los papeles de **esta** caja;
- ✅ usar **este** robot para calcular direcciones;
- ✅ escribir en **este** estante;
- ❌ nada más.

Además, el carné tiene una regla anti-trampas: **solo sirve si el bibliotecario está trabajando para tu biblioteca**. Así, nadie de otra cuenta puede pedirle al bibliotecario que use tu carné para entrar a tus cosas. Esa trampa tiene nombre: el **problema del ayudante confundido** (*confused deputy*), y se evita con las condiciones `aws:SourceAccount` y `aws:SourceArn`.

---

## 5. Dos bibliotecas para comparar

La pregunta del laboratorio era: **¿qué conviene más, armar la biblioteca tú mismo o que te la den hecha?** Así que construimos dos con los mismos papeles.

### Biblioteca 1: "Hazlo tú mismo" (KB vectorial)

Es como **armar tu propio mueble de Lego**: tú eliges las piezas.
- Tú eliges el estante (S3 Vectors).
- Tú eliges el robot de las direcciones (Titan).
- Tú decides cómo cortar las tarjetas (con regla, 300 palabras).
- **Ventaja:** controlas todo y es rápida.
- **Desventaja:** hay más cosas que configurar, y algunas decisiones **no se pueden cambiar** después, como la forma de cortar.

### Biblioteca 2: "Todo incluido" (Managed KB)

Es como **un hotel todo incluido**: llegas, dejas tus papeles y ellos se encargan de todo.
- No eliges estante: lo pone Amazon.
- No eliges robot de direcciones: lo pone Amazon, sin costo extra.
- Corta las tarjetas por capítulos y además lee imágenes y tablas.
- Trae un **segundo revisor** que vuelve a ordenar las tarjetas encontradas, poniendo arriba las más útiles (**re-ranker**).
- **Ventaja:** casi no hay que configurar nada y es más lista.
- **Desventaja:** es más lenta y solo existe en algunas ciudades del mundo (**regiones**). Por ejemplo, no existe en Ohio (`us-east-2`), así que la pusimos en Virginia (`us-east-1`).

---

## 6. Tres formas de preguntarle a la biblioteca

### Forma 1: "Dame las tarjetas" (`Retrieve`)

Le pides a la biblioteca: *"muéstrame las 3 tarjetas que más se parecen a mi pregunta"*. Te las entrega con una **nota de parecido** (el **score**), y **tú** decides qué hacer con ellas. Aquí no participa el robot que habla.

> Ojo: la biblioteca "Hazlo tú mismo" **siempre** te da 3 tarjetas, aunque la tercera no tenga nada que ver. Es como pedirle a alguien "dame tus 3 mejores ideas" cuando solo tiene 2 buenas: igual te da una tercera. La "Todo incluido" es más honesta y, si solo encontró 2 buenas, te da 2.

### Forma 2: "Búscalo y respóndeme" (`RetrieveAndGenerate`)

La biblioteca busca las tarjetas, se las pasa al robot que habla (**Claude**) y el robot te responde en una frase, diciendo **de qué papel sacó cada dato** (las **citas**). **Busca una sola vez.** Solo la tiene la biblioteca "Hazlo tú mismo".

### Forma 3: "El detective" (`AgenticRetrieveStream`)

Solo la tiene la biblioteca "Todo incluido". Aquí trabaja un **detective**:
1. busca una primera vez;
2. piensa: *"¿con esto me alcanza o me falta una pista?"* (**planificar**);
3. si le falta, **vuelve a buscar** otra cosa;
4. cuando tiene todas las pistas, responde.

Es más lento, pero puede **unir pistas que están en papeles distintos** (**multi-hop**, que quiere decir "dar varios saltos").

---

## 7. Las etiquetas de colores (filtros)

¿Recuerdas las etiquetas "atención al cliente" y "producción"? Sirven para decirle a la biblioteca:

> "Busca **solo** entre los papeles con etiqueta azul."

La biblioteca ni siquiera mira los demás. Esto es muy útil para la **seguridad**: si un cliente pregunta algo, solo buscas en los papeles para clientes, y los papeles internos nunca llegan al robot (**control de acceso por documento**).

En la prueba preguntamos por el secado del café honey, que está en un papel de "producción":
- con el filtro **"atención al cliente"**, la biblioteca no encontró la respuesta, y el robot dijo que no podía ayudar en vez de inventar;
- con el filtro **"producción"**, encontró la respuesta: *"entre 18 y 22 días"*.

---

## 8. Las pruebas: ¿qué pasó?

Le hicimos las mismas 6 preguntas a las dos bibliotecas, 3 veces cada una, y medimos cuánto tardaban.

### Llenar la biblioteca (ingesta)

| | "Hazlo tú mismo" | "Todo incluido" |
|---|---|---|
| La primera vez | **5 segundos** | **2 minutos y medio** |
| Cuando nada cambió | **menos de 1 segundo** | **1 minuto** |

La "Todo incluido" lee todo con mucho más cuidado, y eso toma tiempo.

### La pregunta fácil

> "¿Cuántos días tengo para devolver un café?"

- Las dos respondieron bien: **10 días**, el café sin abrir y la válvula intacta.
- "Hazlo tú mismo" tardó **2 segundos**; "Todo incluido", **5 segundos**.
- Detalle curioso: la regla de "Hazlo tú mismo" cortó la sección de devoluciones **por la mitad**. La de "Todo incluido" la guardó completa en una sola tarjeta.

### La pregunta difícil (la más importante)

> "Quiero el café **honey** en suscripción **anual**. ¿Cuánto pago, qué me regalan y **puedo devolverlo** si no me gusta?"

Para responder bien hay que unir **tres pistas de tres papeles distintos**:

1. 📄 Ficha técnica: el café honey es de la línea **"Microlote Reserva"**.
2. 📄 Política: los cafés "Microlote Reserva" **no se pueden devolver**.
3. 📄 Preguntas frecuentes: el plan anual cuesta **920.000 pesos** y regalan un **molino**.

Qué pasó:
- **"Hazlo tú mismo"** buscó **una sola vez** y no encontró la pista 1. Como no sabía que el honey es "Microlote Reserva", respondió **"sí, tienes 10 días para devolverlo"**. ❌ **Eso está mal.** Y es un error peligroso, porque suena muy convincente.
- **"Todo incluido"**, el detective, unió las tres pistas y respondió **"no se puede devolver, salvo que llegue dañado"**. ✅ **Correcto.** Eso sí, tardó **11 segundos** en vez de 3.

### La pregunta sin respuesta

> "¿Tienen tienda en Medellín y qué horario tienen?"

Ninguno de los papeles habla de eso. **Las dos bibliotecas dijeron "no tengo esa información"** en vez de inventar. ✅ A eso se le llama **grounding**: el robot se queda "con los pies en la tierra" y solo usa lo que encontró. El detective además **buscó dos veces** antes de rendirse.

---

## 9. Entonces, ¿cuál es mejor?

**Depende de para qué la quieras:**

| Si necesitas… | Usa… |
|---|---|
| Respuestas rápidas a preguntas sencillas | "Hazlo tú mismo" (KB vectorial) |
| Elegir tú cada pieza (estante, robot, forma de cortar) | "Hazlo tú mismo" |
| Responder preguntas que mezclan varios documentos | "Todo incluido" (Managed KB) |
| No preocuparte por configurar nada | "Todo incluido" |
| Una región donde no existe la "Todo incluido" | "Hazlo tú mismo" |

En una frase: **la rápida es mejor para preguntas sencillas; la detective es mejor para preguntas complicadas.**

---

## 10. Cosas que salieron mal (y lo que aprendimos)

Equivocarse también enseña. Esto fue lo que pasó:

| Qué pasó | Explicado fácil |
|---|---|
| Error `429` al llenar la biblioteca | La primera cuenta de AWS tenía **0 monedas** para usar robots (**cuota 0**). Por más permisos que tengas, sin monedas no se puede. Nos mudamos a otra cuenta |
| Error `403`: *"Your account is currently being verified"* | La otra cuenta era nueva y AWS la estaba **revisando**, como cuando un banco revisa tu cuenta nueva. Esperamos un rato y funcionó |
| La "Todo incluido" no se podía crear en Ohio | No existe en esa ciudad. La pusimos en Virginia, con su propia caja de papeles, porque **la caja tiene que estar en la misma ciudad que la biblioteca** |
| Terraform dijo que el resultado era "inconsistente" | Amazon le agregó a la configuración **valores que nosotros no habíamos escrito**, y Terraform se confundió. Los escribimos nosotros también y todo quedó en orden |
| Se usó una forma de preguntar que no correspondía | Cada biblioteca tiene su forma de preguntar: la "Todo incluido" no acepta "Búscalo y respóndeme", sino al detective |

---

## 11. Las herramientas que usamos

| Herramienta | Qué es, explicado fácil |
|---|---|
| **AWS** | Una ciudad gigante de computadores que alquilas por minutos |
| **Amazon Bedrock** | La parte de esa ciudad donde viven los robots inteligentes |
| **Terraform** | Un **manual de instrucciones de Lego** para la nube. Escribes qué quieres construir y Terraform lo arma. Con un solo comando (`terraform destroy`) también lo **desarma todo**, sin dejar piezas sueltas |
| **Módulo de Terraform** | Una pieza de Lego que **reutilizas**: diseñamos la caja fuerte una vez y la usamos en dos ciudades |
| **Python + boto3** | Los programas que escribimos para hacerle preguntas a la biblioteca |
| **Git y GitHub** | Un **diario** que guarda cada cambio del proyecto, y el lugar donde lo compartimos con el mundo |
| **gitleaks** | Un **detector** que revisa que no hayamos dejado contraseñas olvidadas en el diario |

---

## 12. Cuidar la seguridad y el bolsillo

**Seguridad:** antes de publicar el proyecto revisamos que no tuviera nada privado:
- ni números de cuenta, ni contraseñas, ni el email personal;
- los papeles con datos de la cuenta (el **estado de Terraform**) **nunca se suben**: están en la lista de cosas ignoradas (`.gitignore`).

**Bolsillo:** en la nube, **lo que dejas encendido puede costar plata**. Por eso, al final:
1. desarmamos todo con `terraform destroy` (35 piezas en dos ciudades);
2. revisamos ciudad por ciudad que no quedara nada;
3. buscamos en **las 17 ciudades** disponibles cualquier pieza con la etiqueta del laboratorio;
4. revisamos también la primera cuenta.

Resultado: **no quedó nada encendido**. Todo el laboratorio costó apenas centavos de dólar.

---

## 13. Diccionario rápido

| Palabra | Significado sencillo |
|---|---|
| **Modelo de lenguaje (LLM)** | El robot que sabe hablar y responder |
| **Alucinar** | Cuando el robot inventa algo con mucha seguridad |
| **RAG** | Buscar primero en tus papeles y después responder |
| **Knowledge Base** | La biblioteca de tus papeles para el robot |
| **Data source** | La caja de donde la biblioteca saca los papeles |
| **Ingesta** | Llenar la biblioteca: cortar, calcular direcciones y guardar |
| **Chunk** | Una tarjeta, un pedacito de documento |
| **Chunking** | La forma de cortar los documentos en tarjetas |
| **Solapamiento** | Repetir un poquito de la tarjeta anterior para no perder el hilo |
| **Embedding / vector** | La dirección de una idea en el mapa de los significados |
| **Dimensiones** | Cuántos números tiene esa dirección (aquí, 1024) |
| **Vector store** | El estante que guarda las tarjetas ordenadas por significado |
| **Distancia coseno** | La forma de medir qué tan parecidas son dos ideas |
| **Score** | La nota de parecido entre tu pregunta y una tarjeta |
| **Re-ranker** | El segundo revisor que reordena las tarjetas por utilidad |
| **Metadatos / filtro** | Etiquetas de colores para buscar solo en ciertos papeles |
| **Multi-hop** | Unir pistas de varios documentos para responder |
| **Agéntico** | Que trabaja como detective: planea, busca, revisa y repite |
| **Grounding** | Responder solo con lo que encontraste, sin inventar |
| **Cita** | El papel de donde salió cada dato de la respuesta |
| **Rol de IAM** | El carné con permisos del bibliotecario |
| **Mínimo privilegio** | Dar solo los permisos necesarios, ni uno más |
| **Confused deputy** | La trampa de usar el carné de otro a través de un ayudante; se evita con condiciones en el carné |
| **Región** | La ciudad del mundo donde vive cada pieza en la nube |
| **Cuota** | Las monedas que tienes para usar los robots por minuto |
| **Terraform** | El manual de Lego para armar y desarmar la nube |
