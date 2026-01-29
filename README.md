# Procesador RISC-V Pipeline con Debug Unit UART

## 📌 Descripción general

Este proyecto implementa un **procesador RISC-V con arquitectura pipeline**, desarrollado en **Verilog** y orientado a su ejecución sobre **FPGA**.  
Además, se incorpora una **Debug Unit** que permite la interacción con el procesador mediante **comunicación UART**, facilitando la visualización del estado interno del sistema y la depuración en tiempo real.

El sistema está diseñado para permitir la **programación y reprogramación dinámica del procesador sin necesidad de resintetizar**, cumpliendo con los requerimientos del trabajo final de la materia.

---

## 🧠 Arquitectura del Procesador

El procesador sigue una arquitectura pipeline clásica de **cinco etapas**:

- **IF (Instruction Fetch)**: Búsqueda de la instrucción desde la memoria de programa.
- **ID (Instruction Decode)**: Decodificación de la instrucción y lectura del banco de registros.
- **EX (Execute)**: Ejecución de operaciones aritméticas y lógicas.
- **MEM (Memory Access)**: Acceso a memoria de datos (load/store).
- **WB (Write Back)**: Escritura del resultado en el banco de registros.

---

## ⚠️ Riesgos del Pipeline

Se consideran y gestionan los siguientes tipos de riesgos:

- **Riesgos estructurales**: Conflictos por uso simultáneo de recursos.
- **Riesgos de datos**: Uso de datos antes de que estén disponibles.
- **Riesgos de control**: Decisiones de salto antes de evaluar la condición.

---

## 🧾 Conjunto de Instrucciones Implementadas

### Tipo R (Registro a Registro)
- `add`, `sub`, `sll`, `srl`, `sra`
- `and`, `or`, `xor`
- `slt`, `sltu`

### Tipo I (Inmediato / Carga)
- `addi`, `andi`, `ori`, `xori`
- `slti`, `sltiu`
- `slli`, `srli`, `srai`
- `lb`, `lh`, `lw`, `lbu`, `lhu`
- `jalr`

### Tipo S (Store)
- `sb`, `sh`, `sw`

### Tipo B (Ramificación Condicional)
- `beq`, `bne`

### Tipo U
- `lui`

### Tipo J
- `jal`

---

## 🛠 Debug Unit

La Debug Unit permite la comunicación con una PC a través del protocolo **UART** y ofrece:

- Envío del contenido de los **32 registros generales**.
- Envío del estado de los **latches intermedios del pipeline**.
- Lectura del contenido de la **memoria de datos**.
- Control del modo de ejecución del procesador.

---

## ▶️ Modos de Operación

El sistema soporta dos modos de ejecución:

### 🔁 Modo continuo
- Se envía un comando por UART.
- El procesador ejecuta el programa completo hasta encontrar una instrucción de parada.
- Al finalizar, se transmite el estado interno completo.

### 👣 Modo paso a paso
- Cada comando por UART ejecuta **un ciclo de clock**.
- Se visualiza el estado del sistema en cada paso.
- Ideal para depuración detallada.

En ambos casos, el pipeline debe quedar completamente vacío al finalizar la ejecución.

---

## 📥 Carga y Reprogramación de Programas

El programa a ejecutar debe:

- Estar escrito en **ensamblador RISC-V**.
- Ser traducido a código máquina para su envío por UART.
- Incluir una instrucción de **HALT / STOP**.

El sistema permite:

- Programar y reprogramar la memoria de instrucciones **vía UART**.
- Realizar la carga **sin resintetizar el procesador**.
- Evaluar qué elementos deben resetearse (pipeline, registros, memorias).

---

## ⏱ Clock y Temporización

Durante la integración se analiza:

- El **camino crítico** del sistema.
- La presencia de **skew** y sus consecuencias.
- La **frecuencia máxima de operación**.
- Métricas de temporización utilizando herramientas de **Vivado**.
- Aplicación de la frecuencia óptima al diseño final.

---

## 🧰 Herramientas Utilizadas

- **Verilog HDL**
- **Vivado 2025.2**
- **FPGA (Basys / Spartan)**
- UART para comunicación con PC

---

## 📚 Bibliografía

- *Computer Organization and Design – The Hardware/Software Interface (RISC-V Edition)*  
  David A. Patterson, John L. Hennessy
- Documentación oficial del conjunto de instrucciones **RISC-V**
- *FPGA Prototyping by Verilog Examples* – Pong P. Chu

---

## ✨ Notas Finales

El proyecto prioriza el diseño modular, la observabilidad del sistema y la posibilidad de depuración profunda, apuntando a una implementación clara, extensible y didáctica del pipeline RISC-V.

