REPORT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT_DIR := $(abspath $(REPORT_DIR)/../../../../)
BUILD_DIR := $(ROOT_DIR)/docs/report-resources/build/technical
OUTPUT_DIR := $(ROOT_DIR)/docs/informes
MAIN := informe-tecnico-implementacion-gcp
OUTPUT := $(OUTPUT_DIR)/$(MAIN).pdf
LATEXMK ?= latexmk
FLAGS := -pdf -interaction=nonstopmode -halt-on-error

.PHONY: pdf clean rebuild open

pdf:
	mkdir -p "$(BUILD_DIR)" "$(OUTPUT_DIR)"
	cd "$(REPORT_DIR)" && $(LATEXMK) $(FLAGS) -outdir="$(BUILD_DIR)" $(MAIN).tex
	cp "$(BUILD_DIR)/$(MAIN).pdf" "$(OUTPUT)"

clean:
	cd "$(REPORT_DIR)" && $(LATEXMK) -outdir="$(BUILD_DIR)" -C $(MAIN).tex
	$(RM) "$(OUTPUT)"

rebuild: clean pdf

open: pdf
	@if command -v xdg-open >/dev/null 2>&1; then \
		xdg-open "$(OUTPUT)"; \
	elif command -v open >/dev/null 2>&1; then \
		open "$(OUTPUT)"; \
	else \
		echo "PDF generado en $(OUTPUT)"; \
	fi
