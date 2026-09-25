# 论文构建

```bash
mkdir -p ../../output/pdf
make
make render
```

当前是工程工作稿，不是95至105页终稿。缺少以下真实输入时不得补写结论：三端真机截图、HarmonyOS 6与MindSpore Lite测量、AI供应商真实运行日志、至少5名参与者记录、合法授权的方正小标宋简体与仿宋GB2312字体。

当前机器用Songti SC替代方正小标宋简体、用STFangsong替代仿宋GB2312。获得合法字体后，在`main.tex`替换字体名，再运行`pdffonts`确认嵌入。
