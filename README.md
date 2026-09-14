---

<img width="665" height="841" alt="image" src="https://github.com/user-attachments/assets/c9c64a89-51b2-4f52-89ff-8125fbae6553" />
<img width="815" height="448" alt="image" src="https://github.com/user-attachments/assets/be0ad405-77d5-4fcf-8d36-6c3689862ca7" />

<!-- Theos 图片与命令部分 -->
<table style="width: 100%;">
<tr>
<td style="padding-right: 20px; width: 50%;">
    <img src="./theos.png" style="width: 100%; max-width: 400px; height: auto;" />
</td>
<td style="width: 50%; vertical-align: top;">
    <pre>

    终端执行 克隆 Theos 仓库
    git clone --recursive https://github.com/theos/theos.git

    将 Theos 的路径添加到环境变量中：
    方法一：
    终端执行 直接添加到 ~/theos

    export THEOS=~/theos
    export PATH=$THEOS/bin:$PATH

    终端执行 重新 加载配置：
    source ~/.zshrc

    另一种方法：
    终端执行 打开配置文件 .zshrc
    nano ~/.zshrc

    # Theos 配置  // theos文件夹 的本地路径
    export THEOS=/Users/pxx917144686/theos     

    之后；contron + X 是退出编辑； 按‘y’ 保存编辑退出！

    终端执行 重新 加载配置：
    source ~/.zshrc

</td>
</tr>
</table>

<hr style="border: 1px solid #ccc; margin: 30px 0;">

<!-- Theos 报错说明部分 -->
<details>
<summary> 👉  如果 theos 报错:ld: warning: -multiply_defined is obsolete </summary>

| **theos报错** | **解释** |
|----------|----------|
| **报错** | ld: warning: -multiply_defined is obsolete |
| **解释** | 为什么会出现这个问题？ |
| **原因** | 新版本的 Apple 链接器 (ld64) 不再推荐使用 `-multiply_defined`；Theos 为了兼容旧版本 iOS，才默认加入该选项。 |
| **解决** | 在文件 `theos/makefiles/targets/_common/darwin_tail.mk` 打开文件，搜索找到并删除 `-multiply_defined suppress` |

</details>

<hr style="border: 1px solid #ccc; margin: 30px 0;">
