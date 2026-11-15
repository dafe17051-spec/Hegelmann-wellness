# Hegelmann Wellness y RPE

App web para el primer equipo: wellness diario, RPE de sesión, chat con el preparador físico y panel del staff.

- `index.html`: la app completa (una sola página, sin dependencias).
- `supabase/schema.sql`: tablas y funciones de la base de datos (Supabase). Las tablas no son accesibles directamente; todo pasa por funciones que validan el código del jugador o del staff.

Los jugadores entran con un código personal; el staff, con el código de staff.
