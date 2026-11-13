REPORT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../report)
BUILD_DIR := $(abspath $(REPORT_DIR)/../report-resources/build)
OUTPUT_DIR := $(abspath $(REPORT_DIR)/../informes)
MAIN := Lumina_Retail_Informe
OUTPUT := $(OUTPUT_DIR)/informe-general.pdf
LATEXMK ?= latexmk
FLAGS := -pdf -interaction=nonstopmode -halt-on-error

.PHONY: all architecture pdf clean rebuild open

all: pdf

architecture:
	$(MAKE) -C "$(REPORT_DIR)/../architecture" validate

pdf: architecture
	mkdir -p "$(BUILD_DIR)"
	mkdir -p "$(OUTPUT_DIR)"
	cd "$(REPORT_DIR)" && TEXINPUTS="$(REPORT_DIR)//:$(REPORT_DIR)/../report-resources//:$${TEXINPUTS}:" $(LATEXMK) $(FLAGS) -outdir="$(BUILD_DIR)" $(MAIN).tex
	cp "$(BUILD_DIR)/$(MAIN).pdf" "$(OUTPUT)"

clean:
	cd "$(REPORT_DIR)" && $(LATEXMK) -outdir="$(BUILD_DIR)" -C $(MAIN).tex
	$(RM) "$(OUTPUT)"

rebuild: clean
	$(MAKE) pdf

open: pdf
	@if command -v wslpath >/dev/null 2>&1 && command -v explorer.exe >/dev/null 2>&1; then \
		explorer.exe "$$(wslpath -w "$(OUTPUT)")"; \
	elif command -v xdg-open >/dev/null 2>&1; then \
		xdg-open "$(OUTPUT)"; \
	elif command -v open >/dev/null 2>&1; then \
		open "$(OUTPUT)"; \
	else \
		echo "PDF generado en $(OUTPUT)"; \
	fi
