# 论文字体目录

本目录不通过Git保存或分发商业字体文件。论文要求的“方正小标宋简体”和“仿宋_GB2312”可从方正字库官方[公文写作字库个人家庭版](https://www.foundertype.com/index.php/FontInfo/get_font_office.html)取得，并应根据竞赛论文提交用途确认授权范围。

本地构建使用以下被`.gitignore`排除的文件名：

- `FZXiaoBiaoSong.ttf`，内部字体名`FZXiaoBiaoSong-B05S`
- `FangSong_GB2312.ttf`，内部字体名`FangSong_GB2312`
- `KaiTi_GB2312.ttf`，内部字体名`KaiTi_GB2312`

XeLaTeX按文件路径加载字体，不要求全局安装。缺少这些本地文件时会使用系统字体生成开发预览稿；开发预览稿不作为满足指定字体要求的终稿。
