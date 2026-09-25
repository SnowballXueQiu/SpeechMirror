# 论文构建

## 授权字体

方正字库官方的[办公字库与公文写作字库个人家庭版](https://www.foundertype.com/index.php/FontInfo/get_font_office.html)包含“方正小标宋简体”和“仿宋_GB2312”。这两款字体需要按官网说明登录、下载并取得符合实际用途的授权，不从第三方字体下载站获取，也不把字体文件提交到仓库。

安装授权字体后，可用以下命令核对 XeLaTeX 识别的字体名：

```bash
fc-match 'FZXiaoBiaoSong-B05S'
fc-match 'FangSong_GB2312'
```

`main.tex`会优先使用上述字体；未安装时仅使用 macOS 系统字体生成开发预览稿。提交版必须在构建日志和`pdffonts`结果中确认实际嵌入了授权字体。

```bash
mkdir -p ../../output/pdf
make
make render
```

论文正文只保留已经确定的系统设计、实现与可复现结果。开发、真机、调研和终稿事项统一记录在`../IMPLEMENTATION_CHECKLIST.md`，不放入提交版PDF。
