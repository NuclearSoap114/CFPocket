# 第三方组件与修改

- Swift Markdown 0.9.0 / swift-cmark 0.9.0：Swift 项目的 CommonMark/GFM 解析器，Apache-2.0 with Swift Runtime Library Exception；swift-cmark 同时包含原 cmark/GFM 版权条款。对应 LICENSE/NOTICE 保存在 docs/refactor/licenses，依赖由 Package.resolved 固定。
- SwiftSoup 2.14.3：MIT，由原有 TrainingCore Swift Package 固定依赖；遵守其仓库 LICENSE。
- wasm-clang-runtime v0.1.0：CppStudio，Apache-2.0；源自 Ben Smith/binji 的 wasm-clang。包含 Clang/LLD 22.1.8 WASM 发布资产。Apache LICENSE、LLVM Exceptions、NOTICE 随包位于 Resources/Runtime/cpp。上游 commit 见 research.md。
- 本工程**没有使用该发布包的教学 iostream**。完整标准库重新打包自官方 wasi-sdk 33 的 wasm32-wasip1/noeh libc++，以及官方 Clang resource headers/builtins；libc++ Apache-2.0 WITH LLVM-exception，WASI libc/musl 等许可随包保存。源码内原版权声明保留。二进制编译器本身未从完整 LLVM 源码重建，发布资产 SHA256 在 manifest.json，公开发行前仍需完整供应链与依赖许可审计。
- memfs：从上游 src/memfs/memfs.c、stb_sprintf.h 重建，节点上限8192。shared.js 修改：stdout/stderr fd转发、USTAR prefix路径兼容。主管 Worker 与本地运行协议由本项目编写。
- Pyodide 314.0.7：MPL-2.0（及项目随附的多组件许可），其中 CPython 3.14.2 使用 Python Software Foundation license。LICENSE-pyodide.txt、LICENSE-python.txt位于 Resources/Runtime/python。仅捆绑 core+stdlib，不安装远程第三方包。正式发行前需要补完核心 WASM 中全部传递组件 notice 的逐项清单；当前不声称许可审计完成。
- KaTeX 0.19.1：MIT，Resources/Reader/LICENSE；包含其字体资源。只用于清洗后的局部内容，trust=false、maxExpand=1000。
- Codeforces 题面、题解、商标和提交资料不是本项目原创，也未因此获得再分发或商业化许可。运行环境不预装这些正文；用户按需从官方获取并在本机缓存。公开发行前单独核验缓存、翻译、展示和商业用途的权限，不能因为能抓取就无限转载。

自用验证不等于审核、许可证与内容授权均已完成。不得在没有完成上述审计时直接将当前包宣传为可上架发行版本。
