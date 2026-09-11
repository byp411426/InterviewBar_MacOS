const HOST = 'app.interviewbar.macos';
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => chrome.contextMenus.create({
    id: 'interviewbar-import', title: '加入面试日程（识别选中文字）', contexts: ['selection']
  }));
});
function safeURL(value) {
  try { const url = new URL(value); return ['https:', 'http:'].includes(url.protocol) ? url.origin + url.pathname : ''; }
  catch { return ''; }
}
async function send(text, title, sourceURL) {
  if (!text?.trim()) throw new Error('请先选中邮件正文，或把已复制的文字粘贴到扩展里。');
  if (new TextEncoder().encode(text).length > 60000) throw new Error('正文太长，请只选择本次招聘通知。');
  const reply = await chrome.runtime.sendNativeMessage(HOST, { text, title, sourceURL: safeURL(sourceURL) });
  if (!reply?.ok) throw new Error(reply?.error || '应用没有收到内容，请重试。');
  await chrome.action.setBadgeText({text: ''});
  return reply;
}
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== 'interviewbar-import') return;
  try { await send(info.selectionText, tab?.title || '', info.pageUrl || ''); }
  catch (error) {
    await chrome.action.setBadgeText({text: '!'});
    await chrome.action.setBadgeBackgroundColor({color: '#ae3b31'});
    await chrome.storage.session.set({lastError: error.message});
  }
});
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || message.action !== 'import') return;
  send(message.text, message.title, message.sourceURL).then(respond).catch(error => respond({ok: false, error: error.message}));
  return true;
});
