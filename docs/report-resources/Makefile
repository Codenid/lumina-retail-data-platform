REPORT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../report)
BUILD_DIR := $(abspath $(REPORT_DIR)/../report-resources/build)
MAIN := Lumina_Retail_Informe
LATEXMK ?= latexmk
FLAGS := -pdf -interaction=nonstopmode -halt-on-error

.PHONY: all pdf clean rebuild open

all: pdf

pdf:
	mkdir -p "$(BUILD_DIR)"
	cd "$(REPORT_DIR)" && TEXINPUTS="$(REPORT_DIR)//:$(REPORT_DIR)/../report-resources//:$${TEXINPUTS}:" $(LATEXMK) $(FLAGS) -outdir="$(BUILD_DIR)" $(MAIN).tex
	cp "$(BUILD_DIR)/$(MAIN).pdf" "$(REPORT_DIR)/$(MAIN).pdf"

clean:
	cd "$(REPORT_DIR)" && $(LATEXMK) -outdir="$(BUILD_DIR)" -C $(MAIN).tex
	$(RM) "$(REPORT_DIR)/$(MAIN).pdf"

rebuild: clean
	$(MAKE) pdf

open: pdf
	@if command -v wslpath >/dev/null 2>&1 && command -v explorer.exe >/dev/null 2>&1; then \
		explorer.exe "$$(wslpath -w "$(REPORT_DIR)/$(MAIN).pdf")"; \
	elif command -v xdg-open >/dev/null 2>&1; then \
		xdg-open "$(REPORT_DIR)/$(MAIN).pdf"; \
	elif command -v open >/dev/null 2>&1; then \
		open "$(REPORT_DIR)/$(MAIN).pdf"; \
	else \
		echo "PDF generado en $(REPORT_DIR)/$(MAIN).pdf"; \
	fi
