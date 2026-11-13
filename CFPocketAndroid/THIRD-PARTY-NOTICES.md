# 第三方组件

本目录保留相关许可文件；这是个人使用的开发交付，不代表已完成公开商店发行所需的完整许可和内容授权审核。

- AndroidX WebKit1.12.1、DocumentFile1.1.0：Apache2.0；许可在 `app/src/main/assets/web/licenses/AndroidX-LICENSE.txt`，Gradle解析传递依赖。
- Marked15.0.12：MIT；`web/licenses/marked-LICENSE.md`。
- DOMPurify3.2.7：Apache2.0或MPL2.0双许可；`web/licenses/DOMPurify-LICENSE.txt`。
- KaTeX0.19.1及字体：MIT；`Reader/package/LICENSE`。禁用受信任HTML扩展，限制公式展开。
- wasm-clang-runtime v0.1.0 / CppStudio：Apache2.0，派生自 binji/wasm-clang。Clang/LLD22.1.8二进制来自上游发布资产；相关NOTICE、LLVM许可与哈希在`Runtime/cpp`及`Runtime/manifest.json`。
- 完整libc++/WASI系统库来自官方 wasi-sdk33，无教学版iostream。许可涉及Apache2.0 WITH LLVM-exception、WASI libc、musl，原始许可保存在`Runtime/cpp`。memfs节点上限8192，shared.js包含stdout/stderr和USTAR路径补丁。
- Pyodide314.0.7 / CPython3.14.2及其核心依赖：原始合并许可见`Runtime/python/LICENSE-pyodide.txt`和`LICENSE-python.txt`。无远程第三方Python包安装。
- Android适配新增独立受限来源的消息桥，以及C++启动前的WebView能力检测；其余执行器基于本项目已有iOS实现。
- Codeforces题面、题解和商标归原权利人；APK不预装其题面或个人资料。用户按需从官方读取、缓存在自己设备中。

参考来源：

- https://developer.android.com/develop/ui/views/layout/webapps/load-local-content
- https://developer.android.com/training/data-storage/shared/documents-files
- https://developer.android.com/develop/ui/views/layout/webapps/dark-theme
- https://github.com/cppstudio-io/wasm-clang-runtime/releases/tag/v0.1.0
- https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-33
- https://github.com/pyodide/pyodide/releases/tag/314.0.7
- https://github.com/markedjs/marked
- https://github.com/cure53/DOMPurify
- https://katex.org/


### 洛谷内容来源（0.2）

题目评级与社区题解来自 https://www.luogu.com.cn/ 。正文版权归原作者所有，文章内保留作者与原文链接；不随安装包打包真实题解。题号对应方式参考 Codeforces Better 的功能行为（https://github.com/beijixiaohu/OJBetter），适配器和阅读界面独立实现，未复制其 GPL 脚本代码。读取并核对洛谷当前公开网页内嵌数据结构，不将网页原有脚本注入本地阅读器。
