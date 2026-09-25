SHELL := /bin/sh

.PHONY: all clean render

all:
	mkdir -p build
	mkdir -p ../../output/pdf
	latexmk -xelatex -interaction=nonstopmode -halt-on-error -outdir=build main.tex
	cp build/main.pdf ../../output/pdf/SpeechMirror项目论文.pdf

render: all
	mkdir -p ../../tmp/pdfs/paper-pages
	pdftoppm -png -r 120 build/main.pdf ../../tmp/pdfs/paper-pages/page

clean:
	latexmk -C -outdir=build main.tex
