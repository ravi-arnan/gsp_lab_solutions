const puppeteer = require('puppeteer-core');
async function getTerminalText() {
  try {
    const browser = await puppeteer.connect({browserURL: 'http://127.0.0.1:9222'});
    const pages = await browser.pages();
    const target = pages.find(p=>p.url().includes('console.cloud.google.com'));
    if(!target) { console.log(new Date().toISOString(), 'no console page'); await browser.disconnect(); return null; }
    const frames = target.frames();
    const shellFrame = frames.find(f=>f.url().includes('shell.cloud.google.com/embeddedcloudshell'));
    if(!shellFrame) { console.log(new Date().toISOString(), 'no shell frame'); await browser.disconnect(); return null; }
    const text = await shellFrame.evaluate(() => {
      const acc = document.querySelector('.xterm-accessibility-tree');
      return acc ? acc.innerText.slice(-7000) : document.body.innerText.slice(-7000);
    });
    await browser.disconnect();
    return text;
  } catch(e){ console.log('monitor err', e.message); return null; }
}
async function loop(){
  for(let i=1;i<=80;i++){
    const text = await getTerminalText();
    if(text){
      const lines = text.split('\n').slice(-70).join('\n');
      console.log(`\n=== [${new Date().toLocaleTimeString()} ${i}/80] ===`);
      console.log(lines.slice(-4000));
      if(text.includes('SELESAI!')) {
        console.log('*** SELESAI DETECTED ***');
        // keep monitoring a bit then exit
      }
      if(text.includes('Project :') && text.includes('qwiklabs')) {
        // show progress
      }
    }
    await new Promise(r=>setTimeout(r,30000));
  }
}
loop();
