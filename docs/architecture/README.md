# Arquitectura canónica

## Arquitectura vigente

La versión aprobada para publicación en informes y portales es la [exportación SVG](generated/arquitectura-archimate.svg). El archivo [`RetailSmart_ArquitecturaSolución.archimate`](RetailSmart_ArquitecturaSolución.archimate) conserva el modelo editable y debe mantenerse alineado con esta vista.

## Control de versión

| Versión | Fecha | Alcance |
|---|---|---|
| 3.2 | 20 de noviembre de 2026 | Arquitectura vigente alineada con la exposición de datos, los recorridos de negocio, las aplicaciones consumidoras y la documentación final del proyecto. |

## Artefactos

- [Arquitectura vigente en SVG](generated/arquitectura-archimate.svg)
- [Arquitectura vigente en PDF](generated/arquitectura-archimate.pdf)
- [Modelo editable ArchiMate](RetailSmart_ArquitecturaSolución.archimate)
- [Diagrama de red](../report-resources/figures/arquitectura/09_arquitectura_red_overview.pdf)

## Validar

```bash
make -C docs/architecture validate
```

Cuando cambie la arquitectura vigente, actualiza conjuntamente el SVG, su exportación PDF y el modelo editable antes de regenerar los informes.
