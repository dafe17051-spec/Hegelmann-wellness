# Hegelmann Wellness & RPE

Web app for the first team: daily wellness, session RPE, chat with the fitness coach and a staff dashboard.

- `index.html`: la app completa (una sola página, sin dependencias).
- `supabase/schema.sql`: tablas y funciones de la base de datos (Supabase). Las tablas no son accesibles directamente; todo pasa por funciones que validan el código del jugador o del staff.

Los jugadores entran con un código personal; el staff, con el código de staff.
