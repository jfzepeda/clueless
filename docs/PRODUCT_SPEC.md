> **Actualización de modos (solicitud posterior del usuario):** Live Transcription incorpora el chat de preguntas y respuestas bajo demanda. AI Assistant pasa a llamarse Auto Answer y, después de cada pausa de voz o al soltar Push-to-Listen, responde las preguntas detectadas o resume el turno si no hay preguntas. Ambos modos comparten transcripción y chat. Esta actualización sustituye las descripciones y ajustes anteriores de sugerencias automáticas/cooldown.

# Audio Router
**Product & Technical Specification — v1.0**

**Plataforma:** macOS  
**Tipo:** Native Menu Bar Utility  
**Tecnologías:** Swift, SwiftUI, AppKit, ScreenCaptureKit, Core Audio, OpenAI API  
**Estado:** Especificación para implementación

---

## 1. Objetivo

Desarrollar una aplicación nativa para macOS capaz de capturar, redirigir y procesar el audio generado por otras aplicaciones o por el sistema operativo.

La aplicación deberá:

- Ejecutarse desde la barra de menús de macOS (*menu bar only*).
- Funcionar sin una ventana principal permanente ni icono en el Dock.
- Capturar audio de Zoom, Microsoft Teams, navegadores y otras aplicaciones.
- Permitir capturar todo el audio del sistema o seleccionar aplicaciones específicas cuando la API del sistema lo permita.
- Redirigir audio a un dispositivo de entrada virtual.
- Transcribir audio mediante OpenAI Speech-to-Text.
- Analizar conversaciones mediante modelos de OpenAI para generar respuestas contextuales.
- Mostrar transcripciones y respuestas en una ventana flotante sobre otras aplicaciones.
- Permitir activación temporal mediante combinaciones de teclas o activación continua mediante un toggle.
- No generar respuestas de voz. Toda respuesta producida por OpenAI será exclusivamente texto.

## 2. Experiencia general de usuario

### 2.1 Aplicación en la barra de menús

Al iniciar Audio Router, aparecerá un icono de ondas de audio en la barra superior de macOS.

No deberá aparecer en el Dock durante su funcionamiento habitual.

Al hacer clic en el icono, se desplegará un panel con:

- Estado actual: Idle, Listening, Processing, Error.
- Selector de modo.
- Fuente de audio.
- Toggle **Always Listening**.
- Acción Start/Stop Listening.
- Acción Show/Hide Floating Window.
- Acceso al historial de la sesión.
- Settings.
- Quit.

El menú no deberá permanecer abierto para que funcionen la captura, los atajos o las conexiones de OpenAI.

### 2.2 Indicador de estado

El icono deberá reflejar el estado del motor de audio:

| Estado | Indicador |
|---|---|
| Idle | Icono neutro |
| Capturing | Ondas activas |
| Processing | Indicador de actividad |
| Error | Indicador de advertencia |
| Paused | Icono de pausa |

El sistema nunca deberá indicar que está escuchando cuando la captura no esté funcionando.

### 2.3 Modos de funcionamiento

La aplicación tendrá cuatro modos principales y una función independiente de activación de escucha.

#### Mode 1 — Virtual Microphone

**Propósito:** Convertir audio saliente de macOS en audio disponible como micrófono virtual para otras aplicaciones.

Características:

- Captura de audio del sistema o de aplicaciones compatibles.
- Enrutamiento hacia un dispositivo virtual.
- Posibilidad de escuchar simultáneamente el audio en audífonos.
- Selección del dispositivo de entrada virtual en aplicaciones como ChatGPT, Zoom o Teams.
- Funcionamiento completamente local.
- Sin peticiones a OpenAI.
- Sin ventana flotante obligatoria.
- Sin modificación permanente de los dispositivos predeterminados del usuario.

La primera implementación utilizará BlackHole como dispositivo virtual externo.

Si se requiere enviar audio a BlackHole y a los audífonos simultáneamente, se utilizará una configuración de salida múltiple o un motor de enrutamiento compatible, evitando duplicar o crear bucles de audio.

El cambio automático de dispositivos deberá ser explícito y reversible. No se asumirá que toda aplicación permite modificar dinámicamente su dispositivo de audio.

#### Mode 2 — AI Dictation

**Propósito:** Convertir audio capturado en texto e insertarlo en la aplicación activa.

Flujo:

1. El usuario activa el atajo o inicia la escucha continua.
2. Se captura audio de la fuente seleccionada.
3. El audio se envía a OpenAI STT.
4. La transcripción aparece en la ventana flotante.
5. El texto finalizado puede insertarse en la aplicación que tenía el foco al comenzar el dictado.

Configuración:

- Fuente predeterminada: micrófono físico para dictado.
- Fuente alternativa: audio del sistema.
- Inserción automática: desactivada por defecto.
- Inserción manual mediante botón o atajo.
- Opción de copiar al portapapeles.
- Opción de limpieza de puntuación y formato.

El sistema deberá conservar la referencia de la aplicación y campo que tenía el foco originalmente, y validar que sigan disponibles antes de intentar insertar texto.

No deberá escribir accidentalmente sobre un campo distinto.

#### Mode 3 — Live Transcription

**Propósito:** Convertir audio del sistema en texto continuamente.

Características:

- Captura en tiempo real.
- Transcripciones incrementales.
- Texto provisional y texto confirmado visualmente diferenciados.
- Detección de silencios mediante VAD.
- Identificación de idioma cuando el modelo la soporte.
- Historial cronológico con marcas de tiempo.
- Scroll automático opcional.
- Copiar transcripción.
- Exportar transcripción como TXT o Markdown.
- Pausar y reanudar la captura.
- Mantener la sesión mientras la ventana flotante esté oculta.

Para escucha continua se utilizará preferentemente `gpt-live-transcribe`, sujeto a la disponibilidad y configuración de la API.

Los segmentos confirmados nunca deberán duplicarse en el historial al recibir eventos de actualización.

#### Mode 4 — AI Assistant

**Propósito:** Escuchar una conversación del sistema y ofrecer ayuda contextual mediante respuestas exclusivamente escritas.

La aplicación podrá escuchar reuniones, entrevistas, presentaciones, clases u otras conversaciones.

Flujo:

1. Capturar audio.
2. Obtener la transcripción en tiempo real.
3. Actualizar el contexto de conversación.
4. Identificar turnos relevantes y preguntas.
5. Generar respuestas con un modelo de OpenAI.
6. Mostrar las respuestas en la ventana flotante.

Submodos:

**Automatic Suggestions**

El asistente detectará preguntas o momentos relevantes y podrá sugerir una respuesta automáticamente.

**On-Demand Response**

El asistente escuchará y almacenará el contexto de la sesión, pero solo generará una respuesta cuando el usuario utilice un atajo o presione Generate Response.

**Manual Prompt**

El usuario podrá escribir una instrucción en la ventana flotante, por ejemplo:

- Resume los últimos dos minutos.
- ¿Qué están preguntando?
- Genera una respuesta breve en inglés.
- Explica el concepto que acaban de mencionar.
- ¿Qué acuerdos se han tomado?

Las respuestas deberán considerar el contexto disponible de la sesión.

Restricciones:

- Solo texto como salida.
- Ningún audio generado por IA.
- No iniciar grabaciones ni peticiones sin el consentimiento y configuración correspondientes.
- No inventar información de conversaciones no capturadas.
- Distinguir hechos escuchados de sugerencias generadas.
- Las sugerencias automáticas no deberán bloquear ni interrumpir la captura.
- Debe poder configurarse un prompt de sistema personalizado.

---

## 3. Activación de escucha

La captura de audio será independiente del modo de procesamiento.

### 3.1 Push-to-Listen

El usuario mantiene presionada una combinación global de teclas.

Mientras esté presionada:

- Se habilita la captura.
- Se reciben los fragmentos de audio.
- Se ejecuta el procesamiento del modo seleccionado.

Al soltar:

- Se detiene la adquisición de nuevo audio.
- Se finaliza o confirma el fragmento pendiente.
- Se completan las respuestas ya solicitadas.
- Se conserva el historial de la sesión.

Atajo predeterminado propuesto: **⌃⌥Space**.

### 3.2 Toggle Listening

Una combinación de teclas activa o desactiva la escucha.

Primera pulsación: Start Listening.

Segunda pulsación: Stop Listening.

Atajo predeterminado propuesto: **⌃⌥L**.

### 3.3 Always Listening

Toggle disponible en el menú.

Cuando esté activo:

- La aplicación captura continuamente la fuente seleccionada.
- Los modelos procesan audio según el modo activo.
- La ventana flotante puede estar visible u oculta.
- La captura continúa cuando otra aplicación tiene el foco.
- Se mantiene el contexto durante la sesión.
- La aplicación continúa funcionando en segundo plano mientras macOS y sus permisos lo permitan.

El usuario podrá desactivar la función desde la barra de menús en cualquier momento.

No deberá iniciarse la escucha automáticamente al arrancar la computadora salvo que el usuario haya habilitado expresamente esa preferencia.

### 3.4 Prioridad de activación

Se utilizará un único coordinador de captura para evitar sesiones duplicadas.

Reglas:

- Push-to-Listen podrá iniciar una captura temporal desde Idle.
- Si la escucha continua ya está activa, Push-to-Listen no abrirá una segunda captura.
- El toggle manual será la forma de activar o desactivar la escucha persistente.
- Cambiar de modo conservará la fuente cuando sea compatible.
- Cambiar de modo cerrará o reconfigurará las conexiones de procesamiento que ya no se necesiten.
- Una solicitud explícita de Stop All detendrá inmediatamente la adquisición de audio y cancelará los trabajos activos cuando sea posible.

Todos los atajos serán configurables.

---

## 4. Ventana flotante

### 4.1 Comportamiento

Los modos AI Dictation, Live Transcription y AI Assistant deberán utilizar una ventana flotante.

Propiedades:

- Always on top respecto de las ventanas de aplicaciones normales.
- Movible mediante drag.
- Redimensionable.
- Posición persistente entre sesiones.
- Apariencia nativa de macOS.
- Compatible con modo claro y oscuro.
- Esquinas redondeadas.
- Sombra suave.
- Opción de transparencia.
- Opción de anclar/desanclar.
- Ocultable sin detener la escucha.
- No robar el foco al aparecer una transcripción o respuesta automática.
- No interferir con la escritura en otras aplicaciones.
- Soporte para múltiples monitores.
- Respetar el área visible de la pantalla.

Implementación preferida: `NSPanel` con nivel `.floating`, contenido SwiftUI y configuración de comportamiento para Spaces.

La ventana deberá comportarse como una utilidad flotante y no intentar mostrarse encima de interfaces protegidas del sistema, alertas de seguridad o pantallas de bloqueo.

### 4.2 Estados de interfaz

**Compact Mode**

Mostrar:

- Indicador de escucha.
- Modo actual.
- Actividad de audio.
- Última transcripción o sugerencia breve.
- Expandir.
- Cerrar/ocultar.

**Expanded Mode**

Mostrar:

- Selector entre Transcript y Responses.
- Contenido desplazable.
- Campo para instrucciones del usuario en AI Assistant.
- Copiar texto.
- Pausar captura.
- Fijar ventana.
- Cambiar tamaño.

**Minimized Mode**

Ocultar el contenido y mantener únicamente un indicador flotante pequeño, si el usuario activa esta opción.

Cerrar la ventana significa ocultarla, no detener automáticamente la sesión.

### 4.3 Comportamiento de resultados

Las respuestas de IA aparecerán mediante streaming de texto cuando el endpoint seleccionado lo permita.

En AI Assistant:

- Las respuestas nuevas deberán distinguirse de las anteriores.
- Se mostrará la hora aproximada de generación.
- Cada respuesta podrá copiarse.
- Los resultados anteriores permanecerán accesibles en el historial de sesión.
- El usuario podrá detener una generación en curso.
- Las respuestas no deberán reemplazarse abruptamente por otras nuevas.
- Si llegan varios eventos consecutivos, se aplicará una política de cola o sustitución de sugerencias pendientes, sin interrumpir una respuesta ya visible.

---

## 5. Captura y enrutamiento de audio

### 5.1 Captura nativa

Tecnología principal: `ScreenCaptureKit`.

Se utilizará para capturar audio del sistema y de aplicaciones compatibles sin necesidad de modificar permanentemente la salida de audio del usuario.

Funciones:

- Capturar audio del sistema.
- Seleccionar fuentes compatibles.
- Excluir el audio del proceso de Audio Router.
- Mantener la reproducción normal en el dispositivo de salida del usuario.
- Detectar interrupciones y cambios de dispositivos.
- Recuperarse cuando se desconecten o conecten audífonos.

La captura por aplicación dependerá de las capacidades del sistema operativo y los permisos concedidos.

### 5.2 Captura del micrófono

Se utilizará Core Audio / AVAudioEngine para capturar un micrófono físico cuando el usuario lo seleccione.

No se activará de forma implícita en los modos configurados como System Audio Only.

### 5.3 Pipeline de procesamiento

El flujo compartido será:

Audio Source → Capture Engine → PCM Buffer → Resampling / Channel Conversion → Audio Router → Mode Processor → Output.

El motor deberá:

- Utilizar buffers temporales acotados.
- Preservar la secuencia temporal.
- Convertir canales y frecuencia según el destino.
- Implementar backpressure para conexiones lentas.
- Detectar desconexiones.
- Evitar fugas de memoria durante sesiones prolongadas.
- No bloquear el hilo principal de la interfaz.

### 5.4 Dispositivos virtuales

Para Virtual Microphone se permitirá seleccionar BlackHole como salida de audio virtual.

El sistema deberá detectar si BlackHole está instalado y proporcionar instrucciones de configuración en caso contrario.

La versión inicial no incluirá un driver de audio virtual propio.

### 5.5 Prevención de audio loops

Cuando el motor capture audio del sistema:

- Se excluirá el audio generado por la propia aplicación cuando la API lo permita.
- Las respuestas de OpenAI serán únicamente texto.
- Se evitará la duplicación del mismo flujo.
- El dispositivo virtual no deberá seleccionarse simultáneamente como fuente de recaptura sin una configuración explícita y validada.

---

## 6. Integración con OpenAI

### 6.1 Autenticación

El usuario podrá introducir su OpenAI API Key desde Settings.

La clave se almacenará en macOS Keychain.

No deberá almacenarse en texto plano dentro de UserDefaults, logs ni archivos de configuración.

La aplicación utilizará conexiones TLS y deberá permitir eliminar o reemplazar la clave.

### 6.2 Transcripción en tiempo real

Modelo predeterminado: `gpt-live-transcribe`.

Transporte preferido: WebSocket para sesiones de captura nativa en macOS.

El cliente deberá:

- Establecer una sesión de transcripción.
- Enviar fragmentos de audio.
- Recibir eventos incrementales.
- Confirmar transcripciones finalizadas.
- Manejar VAD y límites de sesión.
- Recuperarse de desconexiones.
- Evitar duplicaciones después de reconectar.

La configuración de idioma y latencia será ajustable.

### 6.3 Procesamiento inteligente

El modo AI Assistant utilizará un modelo de texto configurable mediante la API de OpenAI.

La arquitectura preferida será:

Live STT → Conversation Context Manager → Text Generation API → Floating Panel.

La transcripción continua y la generación de respuestas deberán ejecutarse como procesos lógicos independientes para evitar que el razonamiento o la generación de texto interrumpan la captura.

No se utilizará TTS.

Una integración futura con procesamiento nativo de audio en tiempo real será posible, pero no es obligatoria para la primera versión.

### 6.4 Contexto de conversación

El Context Manager mantendrá:

- Transcripciones confirmadas.
- Marcas de tiempo.
- Instrucciones del usuario.
- Respuestas anteriores relevantes.
- Resumen acumulativo opcional.
- Identificador de sesión.

El sistema podrá compactar información antigua para controlar el consumo de tokens.

Las respuestas deberán basarse en el contexto disponible y no dar a entender que el asistente escuchó contenido que no fue capturado.

### 6.5 Política de generación

En Automatic Suggestions no se llamará al modelo de respuesta por cada token de transcripción.

Se utilizará un controlador con:

- Detección de turnos.
- Identificación de preguntas.
- Umbral de relevancia configurable.
- Cooldown entre sugerencias.
- Cola de peticiones.
- Cancelación de solicitudes obsoletas.

En On-Demand Response solo se generará texto tras una acción explícita del usuario.

### 6.6 Costos

Settings mostrará:

- Modelo de transcripción.
- Modelo de respuesta.
- Duración de captura enviada.
- Estimación de consumo API cuando pueda calcularse.
- Total estimado de la sesión.
- Límite presupuestario configurable.

El límite de presupuesto será preventivo y local. No se presentará como un límite de facturación garantizado del proveedor.

La captura en modo Virtual Microphone no tendrá costo de OpenAI.

---

## 7. Configuración

La pantalla de Settings contendrá las siguientes secciones.

### General

- Launch at Login.
- Menubar Icon Style.
- Restore Previous Mode.
- Restore Floating Window Position.
- Open Floating Window Automatically.
- Follow System Appearance.
- History Retention.

### Audio

- Source: System Audio / Selected Application / Microphone / Mixed Sources.
- Output: Virtual Device.
- Input Device Selection.
- Audio Monitoring.
- Audio Level Meter.
- Sample Rate (automático por defecto).
- BlackHole Detection.
- Exclude Own Application Audio.

### Shortcuts

- Push-to-Listen.
- Toggle Listening.
- Show/Hide Floating Window.
- Generate AI Response.
- Copy Last Response.
- Stop All.

Los atajos deberán detectar conflictos conocidos y permitir reasignaciones.

### OpenAI

- API Key.
- Test Connection.
- Transcription Model.
- Response Model.
- Language Preferences.
- Transcription Delay.
- Custom System Prompt.
- Automatic Suggestions.
- Response Length.
- Context Retention.
- Usage Limits.

### Floating Window

- Opacity.
- Width.
- Height.
- Font Size.
- Pin/Unpin.
- Compact/Expanded.
- Show on All Spaces.
- Default Screen.
- Auto-scroll.
- Show Timestamps.

### Privacy

- Screen/System Audio Capture Permissions.
- Microphone Permission.
- Accessibility Permission.
- Clear History.
- Disable Local Persistence.
- Clear Cached Data.
- Confirmation Before Uploading Audio.
- Local Session Data Retention.

---

## 8. Arquitectura de software

La aplicación se implementará mediante módulos separados.

```text
AudioRouterApp
│
├── AppLifecycle
│   ├── MenuBarController
│   ├── LaunchAtLoginManager
│   └── PermissionManager
│
├── Interface
│   ├── MenuBarView
│   ├── FloatingPanelController
│   ├── FloatingPanelView
│   ├── SettingsView
│   └── SessionHistoryView
│
├── AudioCore
│   ├── SystemAudioCapture
│   ├── MicrophoneCapture
│   ├── AudioBufferManager
│   ├── AudioFormatConverter
│   ├── AudioSourceRouter
│   ├── VirtualDeviceManager
│   └── AudioSessionCoordinator
│
├── Modes
│   ├── VirtualMicrophoneMode
│   ├── DictationMode
│   ├── TranscriptionMode
│   └── AIAssistantMode
│
├── OpenAI
│   ├── APIClient
│   ├── RealtimeTranscriptionClient
│   ├── TextGenerationClient
│   ├── ContextManager
│   ├── ResponseTriggerEngine
│   └── UsageTracker
│
├── Input
│   ├── GlobalHotkeyManager
│   ├── ListeningStateMachine
│   └── TextInsertionService
│
├── Persistence
│   ├── SettingsStore
│   ├── SessionStore
│   └── KeychainService
│
└── Diagnostics
    ├── AudioDiagnostics
    ├── ConnectionMonitor
    └── ErrorReporter
```

### 8.1 Estado global

El coordinador distinguirá tres dimensiones:

**Capture State**

- Idle
- Starting
- Capturing
- Stopping
- Failed

**Processing State**

- Disabled
- Connecting
- Ready
- Processing
- Reconnecting
- Failed

**UI State**

- Hidden
- Compact
- Expanded
- Minimized

Los estados deberán gestionarse de manera independiente.

Por ejemplo, podrá existir Capturing + Processing + Hidden.

Ocultar la ventana flotante nunca deberá cambiar implícitamente Capture State.

### 8.2 Concurrencia

Usar Swift Concurrency cuando sea apropiado.

La captura y el procesamiento deberán ejecutarse fuera del hilo principal.

Las actualizaciones de UI se entregarán al MainActor.

Los buffers se procesarán secuencialmente o con mecanismos que preserven el orden cuando sea necesario.

---

## 9. Persistencia e historial

El sistema mantendrá una sesión lógica para cada periodo de trabajo.

Datos opcionales por sesión:

- Fecha de inicio y final.
- Modo utilizado.
- Fuente seleccionada.
- Transcripción confirmada.
- Respuestas generadas.
- Instrucciones manuales.
- Metadatos de uso y errores no sensibles.

Predeterminado:

- Historial conservado solo durante la sesión.
- No almacenar audio crudo en disco.
- Guardado persistente de transcripciones desactivado hasta que el usuario lo habilite.
- Al cerrar una sesión sin persistencia, eliminar su contenido de la memoria gestionada por la aplicación.

Se permitirá exportar manualmente el texto.

---

## 10. Permisos y seguridad

La aplicación solicitará únicamente los permisos necesarios para cada función.

**System Audio Capture:** requerido para capturar audio del sistema mediante las APIs correspondientes.

**Microphone:** requerido solamente para capturar un micrófono físico.

**Accessibility:** requerido para insertar texto en otras aplicaciones o realizar acciones que lo necesiten.

**Global Keyboard Monitoring:** solo cuando la implementación de atajos elegida requiera permisos adicionales.

El sistema deberá explicar el propósito de cada permiso.

Si un permiso es rechazado:

- No bloquear funciones independientes.
- Mostrar información clara.
- Ofrecer acceso a la configuración de macOS.
- No intentar evadir restricciones del sistema.

Al capturar reuniones o llamadas se deberá informar al usuario de que es responsable de contar con los permisos y consentimientos correspondientes.

---

## 11. Manejo de errores

### OpenAI unavailable

- Mantener la interfaz responsiva.
- Mostrar Connection Error.
- Reintentar con backoff limitado.
- Permitir detener manualmente los reintentos.
- No acumular audio ilimitadamente para enviarlo después.
- Descartar buffers antiguos según una política documentada.

### Audio device changed

- Detectar cambio.
- Reconectar si resulta seguro.
- Actualizar indicador.
- Conservar la transcripción existente.

### Capture permission revoked

- Detener la captura.
- Actualizar estado.
- Solicitar recuperación manual del permiso.

### API rate limit or budget reached

- Detener nuevas peticiones afectadas.
- Mostrar información de error.
- Evitar reintentos infinitos.
- Conservar los resultados locales existentes.

### Sleep / Wake

- Suspender el motor durante reposo.
- No simular una sesión activa durante la suspensión.
- Reconectar tras el despertar cuando el usuario conserve activa la escucha continua y el sistema lo permita.

---

## 12. Criterios de aceptación

### Aplicación

- [ ] Se ejecuta desde la barra de menús.
- [ ] No aparece icono permanente en el Dock.
- [ ] Puede abrir Settings sin una ventana principal.
- [ ] La captura continúa cuando el menú está cerrado.
- [ ] Se puede salir desde Quit.

### Audio

- [ ] Captura audio reproducido por una aplicación compatible.
- [ ] Captura audio de Zoom o Teams usando una fuente autorizada.
- [ ] Puede capturar todo el audio del sistema.
- [ ] El usuario sigue escuchando el audio normalmente.
- [ ] El modo virtual permite seleccionar BlackHole como destino.
- [ ] No se producen bucles de audio en la configuración predeterminada.
- [ ] Los cambios de dispositivos no provocan bloqueos de la aplicación.

### Listening

- [ ] Push-to-Listen captura únicamente durante su activación.
- [ ] Toggle Listening funciona desde cualquier aplicación compatible.
- [ ] Always Listening persiste hasta que se desactive o termine la sesión.
- [ ] Los atajos pueden personalizarse.
- [ ] Stop All detiene la adquisición inmediatamente.
- [ ] El estado del menú refleja correctamente la captura real.

### OpenAI

- [ ] La API Key se conserva en Keychain.
- [ ] La transcripción muestra resultados incrementales.
- [ ] Los resultados confirmados no se duplican.
- [ ] AI Assistant conserva contexto entre turnos.
- [ ] On-Demand Response genera una respuesta tras la acción del usuario.
- [ ] Automatic Suggestions no envía peticiones por cada fragmento.
- [ ] No se genera audio de salida.
- [ ] Los errores de red no provocan pérdida de control sobre la captura.

### Ventana flotante

- [ ] Se mantiene sobre las ventanas normales.
- [ ] Se puede mover y redimensionar.
- [ ] Mantiene la posición configurada.
- [ ] No roba el foco al actualizar contenido.
- [ ] Permite copiar resultados.
- [ ] Se puede ocultar sin detener la captura.
- [ ] Puede cambiar de Compact a Expanded.
- [ ] Funciona con múltiples monitores y Spaces.
- [ ] Respeta Light/Dark Mode.

---

## 13. Alcance de la primera versión (MVP)

Implementar primero:

1. Aplicación nativa de barra de menús.
2. Captura de audio del sistema.
3. Detección y configuración de BlackHole.
4. Virtual Microphone.
5. Push-to-Listen y Toggle Listening.
6. Always Listening.
7. OpenAI Live STT.
8. OpenAI AI Assistant con salida únicamente de texto.
9. Ventana flotante always-on-top.
10. API Key almacenada en Keychain.
11. Configuración básica de fuentes, atajos y modelos.
12. Historial de sesión en memoria.
13. Estados, errores y reconexión.

### Segunda fase

- Dictado con inserción automática en cualquier campo compatible.
- Selección y mezcla avanzada de fuentes.
- Prompt presets.
- Exportación avanzada.
- Estadísticas de uso.
- Resúmenes automáticos.
- Optimización del contexto en sesiones largas.
- Configuración avanzada de varios monitores.

---

## 14. Decisiones finales de producto

- La aplicación será **menu bar only**.
- No habrá ventana principal permanente.
- Los modos que utilizan OpenAI tendrán una ventana flotante.
- La ventana flotante podrá ocultarse sin interrumpir el funcionamiento.
- OpenAI producirá únicamente texto.
- El audio de Zoom, Teams y demás aplicaciones podrá capturarse mediante interfaces compatibles de macOS.
- Existirán activación temporal por atajo y activación continua por toggle.
- El asistente podrá escuchar continuamente y responder bajo demanda.
- Las respuestas automáticas serán configurables.
- Los resultados serán copiables.
- No se utilizará un servidor intermedio obligatorio: la primera versión será un cliente macOS que se conecta directamente a OpenAI mediante la API Key del usuario.
- La captura será independiente del procesamiento y de la visibilidad de la interfaz.

**Resultado esperado:** una herramienta ligera de macOS capaz de utilizar el audio de cualquier aplicación compatible como entrada para un micrófono virtual o para un asistente inteligente, con control global desde la barra de menús y respuestas exclusivamente escritas en una ventana flotante.