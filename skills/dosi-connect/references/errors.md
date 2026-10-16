# Error → what the user sees

Every dosi error under `--format json` carries `code`, `message`, and often
`hint`, `candidates`, `suggested_retry`. Say it in three lines; never paste the
raw JSON or a stack trace; give exactly **one** next step.

```
✗ <what happened, in the user's terms>
  原因：<one-sentence cause>
  下一步：<one action>
```

| code | 发生了什么 | 下一步 | auto-recover? |
|---|---|---|---|
| `dosi_installing` | — (say nothing) | wait ~5 s, rerun the same command (up to 6 times) | yes |
| `install_failed` | dosi 没装上 | the `hint` command (China: `DOSI_SOURCE=oss`) | no |
| `missing_env` | 连不上 `<name>` | `! export <VAR>=...`（不要把值贴到对话里） | no |
| `auth_failed` | `<name>` 认证失败 | 检查 `<VAR>` 的值是否正确，重新 export 后再试 | no |
| `unsupported_auth` | `<profile>` 用的认证方式暂不支持 | 改用 key-pair 或 密码 + 环境变量（给出模板） | no |
| `network_blocked` | 到 `<host>` 的网络不通 | 检查 VPN / 代理；或在 agent 中放开网络权限 | no |
| `unsupported_dialect` | dosi 暂不支持 `<warehouse>` | 列出已支持的数仓（`dosi info --format json` 的 `dialects`） | no |
| `connection_not_found` | 没有叫 `<name>` 的连接 | 从 `dosi connection list --format json` 里选，或重新 `migrate conf` | partly |
| validate `compile_errors` / `issues` | — (say nothing) | fix the model yourself; tell the user only after 3 failed fixes | yes |
| `detail_fanout`, `ambiguous_join_path` | — (say nothing) | rerun with `suggested_retry`; ask only if both readings are plausible business meanings | yes |
| `unknown_metric`, `unknown_field` | 没有 `<x>` | 「最接近的有：<top 3 candidates>」— pick one if the intent is clear, else ask | partly |
