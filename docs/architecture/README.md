# Arquitectura canónica

El único modelo editable de la arquitectura es
[`RetailSmart_ArquitecturaSolución.archimate`](RetailSmart_ArquitecturaSolución.archimate).
Las exportaciones ubicadas en `generated/` son artefactos derivados para
informes y visualización; no deben editarse manualmente ni convertirse en otra
fuente de decisiones.

Para validar que el informe tiene disponibles las exportaciones:

```bash
make -C docs/architecture validate
```

El informe LaTeX usa `generated/arquitectura-archimate.pdf`. Por tanto, el PDF
del informe siempre muestra la exportación asociada al modelo canónico.
