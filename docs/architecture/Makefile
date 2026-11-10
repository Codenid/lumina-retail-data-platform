MODEL := RetailSmart_ArquitecturaSolución.archimate
GENERATED := generated

.PHONY: validate clean

validate:
	@test -s "$(MODEL)"
	@test -s "$(GENERATED)/arquitectura-archimate.pdf"
	@test -s "$(GENERATED)/arquitectura-archimate.svg"
	@echo "Arquitectura canónica validada: $(MODEL)"
	@echo "Exportaciones para informes: $(GENERATED)/"

clean:
	$(RM) "$(GENERATED)/arquitectura-archimate.pdf" "$(GENERATED)/arquitectura-archimate.svg"
