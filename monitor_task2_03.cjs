const puppeteer = require('puppeteer-core');
async function check(){
  try{
    const browser = await puppeteer.connect({browserURL: 'http://127.0.0.1:9222'});
    const target = (await browser.pages()).find(p=>p.url().includes('qwiklabs-gcp-03-f4b1b4a29d7e'));
    const frames = target.frames();
    const shellFrame = frames.find(f=>f.url().includes('shell.cloud.google.com/embeddedcloudshell'));
    await shellFrame.evaluate(() => {
      const ta = document.querySelector('textarea.xterm-helper-textarea');
      if(ta) ta.focus();
    });
    await new Promise(r=>setTimeout(r,600));
    // type check command
    await target.keyboard.type('gcloud compute ssl-certificates describe apigee-cert --global --format="value(managed.status)" && echo "---" && curl -k -s -o /dev/null -w "%{http_code}" https://136.69.0.226.nip.io/hello-world; echo " curl done"');
    await target.keyboard.press('Enter');
    await new Promise(r=>setTimeout(r,9000));
    const text = await shellFrame.evaluate(() => {
      const acc = document.querySelector('.xterm-accessibility-tree');
      return acc ? acc.innerText.slice(-7000) : '';
    });
    console.log(new Date().toLocaleTimeString(), text.slice(-3000));
    await browser.disconnect();
  }catch(e){ console.log('check err', e.message); }
}
async function loop(){
  for(let i=0;i<20;i++){
    await check();
    await new Promise(r=>setTimeout(r,45000));
  }
}
loop();
