package com.codex.cfpocket;

import android.app.Activity;
import android.os.Handler;
import android.os.Looper;
import android.net.Uri;
import android.webkit.*;
import android.widget.*;
import android.view.View;
import org.json.*;

/** Website login stays in its own WebView, with no app bridge or credential export. */
final class LuoguSession {
  interface Reply { void done(String text, String error); }
  private final WebView web;
  private final LinearLayout pane;
  private final Handler main = new Handler(Looper.getMainLooper());
  private Reply pending;
  private String path;
  private boolean ready = false;
  private int generation = 0;
  private final Runnable returned;
  LuoguSession(Activity activity, FrameLayout root, Runnable returned) {
    this.returned = returned;
    web = new WebView(activity);
    WebSettings settings = web.getSettings(); settings.setJavaScriptEnabled(true); settings.setDomStorageEnabled(true);
    settings.setAllowFileAccess(false); settings.setAllowContentAccess(false); settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
    CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
    pane = new LinearLayout(activity); pane.setOrientation(LinearLayout.VERTICAL); pane.setBackgroundColor(android.graphics.Color.WHITE);
    Button back = new Button(activity); back.setText("返回题解"); back.setOnClickListener(v -> hide()); pane.addView(back);
    pane.addView(web, new LinearLayout.LayoutParams(-1, 0, 1)); root.addView(pane, new FrameLayout.LayoutParams(1,1));
    pane.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
    web.setWebViewClient(new WebViewClient() {
      @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        return request.isForMainFrame() && !("https".equals(request.getUrl().getScheme()) && "www.luogu.com.cn".equals(request.getUrl().getHost()));
      }
      @Override public void onPageFinished(WebView view, String url) { ready = "www.luogu.com.cn".equals(Uri.parse(url).getHost()); if (pending != null && ready) fetch(generation); }
      @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) { if(request.isForMainFrame()) { ready=false; finish(null,"无法连接洛谷，原缓存保留。请重试或完成网站验证。"); } }
    });
  }
  void read(String path, Reply reply) {
    if(!path.matches("/problem/(solution/)?CF[1-9][0-9]*[A-Z][0-9]{0,2}(\\?page=[1-9][0-9]{0,3})?")) { reply.done(null,"无效的洛谷读取路径。"); return; }
    if(pending != null) { reply.done(null,"洛谷正在读取，请稍后重试。"); return; }
    this.path=path; pending=reply; int token=++generation;
    main.postDelayed(()->{ if(token==generation && pending!=null) finish(null,"洛谷响应超时，原缓存保留。可以登录 / 验证后重试。"); },45000);
    if(ready) fetch(token); else web.loadUrl("https://www.luogu.com.cn"+path);
  }
  private void fetch(int token) {
    String script="(async()=>{const abort=new AbortController();const timer=setTimeout(()=>abort.abort(),25000);try{if(location.origin!=='https://www.luogu.com.cn')throw Error('请完成洛谷登录');const response=await fetch("+JSONObject.quote(path)+",{credentials:'same-origin',signal:abort.signal});if(new URL(response.url).origin!==location.origin)throw Error('洛谷返回了其它站点');const html=await response.text();if(html.length>8000000)throw Error('题解页面过大');const node=new DOMParser().parseFromString(html,'text/html').querySelector('script#lentille-context[type=\"application/json\"]');if(!node)throw Error('请完成洛谷网站验证后重试，原缓存仍保留。');const raw=JSON.parse(node.textContent);return JSON.stringify({template:raw.template,status:raw.status,data:raw.data});}finally{clearTimeout(timer);}})().then(text=>window.__pocketLuogu={token:"+token+",text}).catch(e=>window.__pocketLuogu={token:"+token+",error:String(e.message||e)});";
    web.evaluateJavascript(script, v->poll(token,0));
  }
  private void poll(int token, int count) {
    if(token!=generation || pending==null)return;
    web.evaluateJavascript("JSON.stringify(window.__pocketLuogu||null)", value->{
      if(token!=generation || pending==null)return;
      try {
        Object decoded=new JSONTokener(value).nextValue();
        if(decoded instanceof String && !decoded.equals("null")) {
          JSONObject result=new JSONObject((String)decoded);
          if(result.optInt("token")==token) { web.evaluateJavascript("delete window.__pocketLuogu",null); finish(result.optString("text",null),result.optString("error",null)); return; }
        }
      } catch(Exception ignored) {}
      if(count<150)main.postDelayed(()->poll(token,count+1),200);
      else finish(null,"洛谷响应超时，请重试；原缓存保留。");
    });
  }
  private void finish(String text,String error) { Reply reply=pending;pending=null;if(reply!=null)reply.done(text,error); }
  void login() { if(pending!=null)return; pane.setLayoutParams(new FrameLayout.LayoutParams(-1,-1));pane.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_AUTO);pane.bringToFront(); ready=false;web.loadUrl("https://www.luogu.com.cn/auth/login"); }
  boolean visible(){ return pane.getLayoutParams().width == -1; }
  void hide(){pane.setLayoutParams(new FrameLayout.LayoutParams(1,1));pane.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);returned.run();}
  void destroy(){generation++;finish(null,"页面已关闭。");web.destroy();}
}
