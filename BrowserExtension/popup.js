const text = document.querySelector('#text'), status = document.querySelector('#message');
let source = {title: '', sourceURL: ''};
text.addEventListener('input', () => { source = {title: '', sourceURL: ''}; });
async function selection() {
  const [tab] = await chrome.tabs.query({active: true, currentWindow: true});
  if (!tab?.id) throw new Error('请先打开邮件页面。');
  // Do not preserve session tokens from webmail URLs.
  try { const u = new URL(tab.url); source = {title: tab.title || '', sourceURL: u.origin + u.pathname}; } catch {}
  const results = await chrome.scripting.executeScript({target: {tabId: tab.id, allFrames: true}, func: () => window.getSelection()?.toString() || ''});
  const chosen = results.map(r => r.result || '').sort((a,b) => b.length-a.length)[0];
  if (!chosen?.trim()) throw new Error('没有选中文字。请回邮件选中正文，或在下面按 ⌘V 粘贴。');
  text.value = chosen; status.textContent = '已读取选中文字，请点击“识别并送到应用”。';
}
document.querySelector('#selection').onclick = () => selection().catch(e => status.textContent = e.message);
document.querySelector('#send').onclick = async () => {
  const button = document.querySelector('#send'); button.disabled = true;
  try {
    const result = await chrome.runtime.sendMessage({action: 'import', text: text.value, ...source});
    if (!result?.ok) throw new Error(result?.error || '发送失败。');
    status.textContent = '已送到“面试日程”，请在弹出的窗口核对后保存。';
  } catch (e) { status.textContent = e.message + ' 也可直接打开菜单栏 → 粘贴识别邮件。'; }
  finally { button.disabled = false; }
};
chrome.runtime.sendNativeMessage('app.interviewbar.macos', {action: 'ping'}).then(r => {
  document.querySelector('#connection').textContent = r?.ok ? '● 已连接面试日程' : '应用连接失败';
}).catch(() => document.querySelector('#connection').textContent = '应用尚未连接；可先使用菜单栏“粘贴识别邮件”。');
chrome.storage.session.get('lastError').then(r => { if (r.lastError) status.textContent = r.lastError; chrome.storage.session.remove('lastError'); });
selection().catch(() => {});
