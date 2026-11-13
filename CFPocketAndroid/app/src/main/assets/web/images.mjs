// Read-only public images. Website JavaScript, private network URLs and local files remain blocked.
export function imageURL(raw,base='https://www.luogu.com.cn'){
  if(typeof raw!=='string'||!raw.trim())return null;
  try{const u=new URL(raw.trim(),base);if(!['https:','http:'].includes(u.protocol)||u.username||u.password||u.port&&!['80','443'].includes(u.port))return null;
    const host=u.hostname.toLowerCase().replace(/\.$/,'');
    if(!/^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$/.test(host)||/\.(localhost|local|internal|lan|home|test|invalid)$/.test(host))return null;
    u.protocol='https:';u.port='';u.hostname=host==='cdn.luogu.org'?'cdn.luogu.com.cn':host;u.hash='';return u.href;
  }catch{return null;}
}
export function sanitizeImages(root,base){root.querySelectorAll('img').forEach(img=>{const u=imageURL(img.getAttribute('src'),base);if(u){img.src=u;img.setAttribute('referrerpolicy','no-referrer');img.setAttribute('loading','lazy');if(!img.alt)img.alt='题解配图';}else{const label=root.ownerDocument.createElement('p');label.className='muted';label.textContent='图片链接无效，无法加载';img.replaceWith(label);}});return root;}
