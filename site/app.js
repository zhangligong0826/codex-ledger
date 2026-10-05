'use strict';
const version='1.2.0-beta.4';
const base=`https://github.com/zhangligong0826/codex-ledger/releases/download/v${version}/`;
const links={'mac-download':`Codex-Ledger-${version}-macOS-universal.dmg`,'win-x64':`Codex-Ledger-${version}-Windows-win-x64-Setup.exe`,'win-arm64':`Codex-Ledger-${version}-Windows-win-arm64-Setup.exe`,'portable-x64':`Codex-Ledger-${version}-Windows-win-x64-Portable.zip`,'portable-arm64':`Codex-Ledger-${version}-Windows-win-arm64-Portable.zip`};
for(const [id,file] of Object.entries(links))document.getElementById(id).href=base+file;
document.getElementById('release').href=`https://github.com/zhangligong0826/codex-ledger/releases/tag/v${version}`;
const mobile=/Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
document.getElementById('mobile-note').hidden=!mobile;
if(!mobile){const target=/Windows/i.test(navigator.userAgent)?'windows':/Macintosh|Mac OS X/i.test(navigator.userAgent)?'mac':null;if(target)document.getElementById(target).classList.add('recommended');}
const texts=[...document.querySelectorAll('[data-en]')];for(const node of texts)node.dataset.zh=node.innerHTML;
let english=false;
function language(value){english=value;document.documentElement.lang=english?'en':'zh-CN';for(const node of texts)node.innerHTML=english?node.dataset.en:node.dataset.zh;document.getElementById('language').textContent=english?'简体中文':'English';document.getElementById('validation').textContent=english?'Beta validation: automated Mac checks and Windows x64 CI, including UI renders and installer tests. Windows ARM64 is cross-built; physical Windows device acceptance is pending.':'测试版验证：Mac 自动检查与 Windows x64 CI，包含界面渲染和安装检查。Windows ARM64 为交叉构建，Windows 实机验收尚未完成。';}
document.getElementById('language').addEventListener('click',()=>language(!english));language(!navigator.language.toLowerCase().startsWith('zh'));
document.getElementById('copy-brew').addEventListener('click',async()=>{const button=document.getElementById('copy-brew');try{await navigator.clipboard.writeText('brew install --cask zhangligong0826/tap/codex-ledger');button.textContent=english?'Copied':'已复制';}catch{button.textContent=english?'Select and copy the command above':'请选中上方命令复制';}});
