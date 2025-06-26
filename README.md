# zigxel

a microzig-based hub75 panel demo

[zigxel.webm](https://github.com/user-attachments/assets/91c7fec2-ce17-4f4d-890e-a59bb1af747b)

Features:
- Hub75 driver using PIO
- Full 24 bit color support
- embedded images in a custom binary format
- buildtime png->custom binary format conversion
- fire effect
- color effects
- double buffering
- multicore, one core runs scanout and manages pio, the other draws images and effects
