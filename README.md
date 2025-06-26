# zigxel

a microzig-based hub75 panel demo

![video](./zigxel.webm)

Features:
- Hub75 driver using PIO
- Full 24 bit color support
- embedded images in a custom binary format
- buildtime png->custom binary format conversion
- fire effect
- color effects
- double buffering
- multicore, one core runs scanout and manages pio, the other draws images and effects
