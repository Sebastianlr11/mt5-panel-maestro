# 🎛️ Portfolio Manager Pro — Panel Maestro MT5

Panel grafico profesional para MetaTrader 5 que permite gestionar todos tus Expert Advisors desde un solo lugar. Escanea charts activos, identifica Magic Numbers y cierra posiciones con un clic.

---

## ✨ Features

- 🔍 **Escaneo automatico de charts** — Detecta todos los Expert Advisors activos en la terminal cada 2 segundos
- 🔢 **Deteccion de Magic Number** — Parsea plantillas de cada chart para extraer el Magic Number del EA
- 🔎 **Busqueda en tiempo real** — Filtra bots por nombre o Magic Number con busqueda instantanea
- 💀 **Kill Switch con confirmacion** — Boton KILL por cada bot con modal de confirmacion antes de actuar
- ⚡ **Cierre masivo de posiciones** — Cierra todas las posiciones abiertas y ordenes pendientes del Magic seleccionado
- 📊 **Scrollbar interactivo** — Navegacion fluida con scroll por rueda del mouse, arrastre y botones
- 🎨 **UI dark theme profesional** — Diseno oscuro con paleta de colores consistente
- 📐 **Responsive al chart** — Se adapta automaticamente al redimensionar la ventana
- 🛡️ **Validacion de seguridad** — Re-verifica chart y Magic Number antes de ejecutar el cierre
- 📋 **Contador de bots** — Badge con cantidad total de bots y resultados filtrados

---

## 🛠️ Tecnologia

![MQL5](https://img.shields.io/badge/MQL5-2962FF?style=flat-square&logo=metatrader5&logoColor=white)
![MetaTrader 5](https://img.shields.io/badge/MetaTrader_5-4A76A8?style=flat-square&logo=metatrader5&logoColor=white)

| Componente | Detalle |
|---|---|
| **Lenguaje** | MQL5 |
| **Plataforma** | MetaTrader 5 |
| **Tipo** | Expert Advisor (EA) |
| **UI** | Objetos graficos nativos de MT5 |

---

## 📦 Instalacion

1. **Copiar** `Portfolio_Manager_Pro.mq5` a:
   ```
   [Terminal MT5]\MQL5\Experts\
   ```

2. **Compilar** en MetaEditor (`F7`)

3. **Adjuntar al chart** — Arrastrar desde el panel de Navegador a cualquier grafico

4. **Permisos** — Habilitar "Permitir trading algoritmico" en Herramientas → Opciones → Expert Advisors

---

## 📋 Requisitos

- MetaTrader 5 (cualquier broker)
- MetaEditor (incluido con MT5)
- Permiso de trading algoritmico habilitado

---

## 📄 Licencia

MIT
