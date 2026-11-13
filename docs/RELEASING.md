# 更新与发布

正式 Bundle ID `cc.anjing.cs-tool-x`，执行文件 `CSToolX`。稳定源：`https://github.com/anjing-le/cs-tool-x/releases/latest/download/appcast.xml`。

本项目不使用钥匙串。应用使用 ad-hoc 完整性签名；Sparkle 验证签名 feed，并在解压前验证 Ed25519 更新包签名，用户确认安装。尚无 Apple Developer ID、公证或固定证书身份的声明。

## 私钥文件

默认在仓库外：`~/Library/Application Support/cs-tool-x-publisher/update-signing.key`。必须为当前用户所有、权限 0600 的普通文件，目录 0700。可用 `CSTOOLX_UPDATE_KEY_FILE` 指定其他仓库外路径；它只包含文件路径，不放密钥内容。

初次生成（已有文件时只核对并重建公钥文件，不覆盖私钥）：

```sh
swift tools/generate-update-key.swift \
  "$HOME/Library/Application Support/cs-tool-x-publisher/update-signing.key" \
  Resources/update-public-key.txt
```

私钥是本地文件，没有未知的钥匙串密码。请保留安全备份；丢失后不能给旧客户端签发可信更新。源码和 app 仅含公钥，绝不复制私钥。

## 构建与准备

开发包 `.dev`，配置隔离并关闭 OTA：

```sh
python3 scripts/build.py --development
```

正式版本先更新 `version.json`，再构建和准备：

```sh
python3 scripts/build.py
python3 scripts/release.py --previous "/path/to/previous/cs-tool-x.app"
```

首次 0.0.1 不需要 `--previous`。以后核对前后包完整性、Bundle ID、执行文件、公钥、feed、递增版本与 build。Ad-hoc 签名的 cdhash 会随构建改变，不用它宣称稳定发布者身份。

准备脚本生成 ZIP、SHA-256 与 signed appcast，调用 Sparkle `sign_update --ed-key-file`，验证归档/feed 并确认篡改样本被拒绝。不读取钥匙串，不把私钥放进参数/环境变量，不自动上传。

## 发布与线上验证

Git 推送使用 `git@anjing-le:anjing-le/cs-tool-x.git`。检查通过且源代码已提交后，上传 ZIP、SHA-256 和 appcast.xml：

```sh
gh release create v0.0.1 \
  dist/releases/cs-tool-x-0.0.1.zip \
  dist/releases/cs-tool-x-0.0.1.zip.sha256 \
  dist/releases/appcast.xml \
  --repo anjing-le/cs-tool-x --title "cs-tool-x 0.0.1" --notes-file release-notes.md
python3 tools/verify-release.py 0.0.1
```

重新下载真实发布资产并验证签名、长度、版本、URL 和 checksum。线上资产验签通过后，实际下载、确认安装、重启仍由用户验收。第三方 Mac 的首次下载启动兼容性仍需实测。

参考：[Sparkle 发布更新](https://sparkle-project.org/documentation/publishing/)、[EdDSA 与签名 feed](https://sparkle-project.org/documentation/)。
