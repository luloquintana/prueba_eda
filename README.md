# Prueba Técnica - Análisis de datos transacciones
Repositorio para desarrollar un proyecto de análisis de datos senior 

## Estructura del repositorio

prueba_tecnica_[tu_nombre]/
├── README.md
├── prueba_tecnica.pdf
├── bloque0_auditoria.sql
├── bloque0_auditoria.md
├── bloque1_queries.sql
├── bloque2_modelo.pdf              # dbdiagram.io/Lucidchart
├── bloque2_decisiones.md
├── bloque3_analisis.ipynb
├── bloque3_visualizaciones/
├── bloque4_kpi_framework.md
├── bloque5_dashboard.pbix|twbx     # Looker Studio
└── bloque5_presentacion_EN.pdf

## Cómo usar este repostiorio

### Carga de datos
1. Crear un dataset en BigQuery sandbox para cada dataset (6 en total, ver prueba_tecnica.pdf).
2. Bloques 0 -1: ejecutar los `.sql` directamente en el editor de BigQuery como consulta.
3. Bloque 2: generar structura de un star schema para el caso de uso.
4. Bloque 3: abrir `bloque3_analisis.ipynb` en Jupyter/Colab. Requiere `pandas`, `scipy`, `matplotlib`/`seaborn`. Si se conecta directo a BigQuery, usar `pandas-gbq` o exportar las vistas del Bloque 1 a CSV.
5. Bloque 4: Uso de North Star Metric. Ajustar los targets sugeridos y verificar cobertura de las 3 dimensiones requeridas (productividad, experiencia, proveedor).
6. Bloque 5: el dashboard se conecta directamente a las vistas de BigQuery generadas en el Bloque 1.

## Uso de IA
Se utilizó Claude (Anthropic) como asistente durante el desarrollo de esta prueba. 
Documentación de transparencia:

Bloque 0: Generación de queries SQL para las 8 dimensiones de auditoría de calidad de datos a partir del diccionario de datos. Se ejecutaron contra los datos reales, se ajustaron umbrales de tolerancia (ej. 1% en consistencia, 3 días en frescura) según el comportamiento observado, y se documentaron manualmente los hallazgos y decisiones.
Bloque 1: Estructura de las 6 queries avanzadas. 
Bloque 4: Estructura de la tabla de KPIs y sugerencias, categorización leading/lagging. 
