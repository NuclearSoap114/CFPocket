package com.codex.cfpocket;

import android.app.*;
import android.os.*;
import android.content.*;
import android.net.Uri;
import android.graphics.Color;
import android.view.*;
import android.webkit.*;
import android.widget.*;
import android.util.AtomicFile;
import android.security.keystore.*;
import androidx.webkit.*;
import androidx.documentfile.provider.DocumentFile;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.util.*;
import java.util.concurrent.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;

/** App UI, executable code and authenticated website live in three separate WebViews. */
public class MainActivity extends Activity {
  private static final String APP="https://appassets.androidplatform.net", RUNTIME="https://runtime.cfpocket.local";
  private final Handler main=new Handler(Looper.getMainLooper());
  private final ExecutorService files=Executors.newSingleThreadExecutor(), network=Executors.newFixedThreadPool(3);
  private LuoguSession luogu;
  private WebView ui,runtime,official; private FrameLayout root; private LinearLayout browserPane;
  private String pickerID,pickerMode,exportText,runID,previousTree; private boolean runtimeReady=false,closing=false;
  private AtomicFile stateFile; private SharedPreferences prefs;
  @Override public void onCreate(Bundle saved) {
    super.onCreate(saved); WebView.setWebContentsDebuggingEnabled((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE)!=0); prefs=getSharedPreferences("private",MODE_PRIVATE); stateFile=new AtomicFile(new File(getFilesDir(),"state.json"));
    if(prefs.contains("pendingTreePrevious")){String old=prefs.getString("pendingTreePrevious","");if(old.isEmpty())prefs.edit().remove("tree").remove("pendingTreePrevious").commit();else prefs.edit().putString("tree",old).remove("pendingTreePrevious").commit();}
    root=new FrameLayout(this); setContentView(root);applyAppearance();
    root.setOnApplyWindowInsetsListener((v,insets)->{if(Build.VERSION.SDK_INT>=30){android.graphics.Insets b=insets.getInsets(WindowInsets.Type.systemBars()|WindowInsets.Type.ime());v.setPadding(b.left,b.top,b.right,b.bottom);}else v.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());return insets;});
    ui=localWeb(APP,false); root.addView(ui,new FrameLayout.LayoutParams(-1,-1));
    android.content.pm.PackageInfo engine=WebView.getCurrentWebViewPackage();
    int engineMajor=0;try{engineMajor=Integer.parseInt(engine.versionName.split("\\.")[0]);}catch(Exception ignored){}
    if(engineMajor<111){new AlertDialog.Builder(this).setTitle("请更新 Android System WebView").setMessage("当前系统网页组件过旧。基础界面需要111或更新版本；离线C++需要137或更新版本。更新后重新打开 App 即可。").setPositiveButton("知道了",(d,w)->finish()).show();return;}
    if(!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)){new AlertDialog.Builder(this).setTitle("请更新 Android System WebView").setMessage("本机浏览器组件太旧，更新后才能安全使用 CF Pocket。").setPositiveButton("知道了",(d,w)->finish()).show();return;}
    WebViewCompat.addWebMessageListener(ui,"Native",Collections.singleton(APP),(view,message,origin,isMain,reply)->{
      if(!isMain || !APP.equals(origin.toString()))return;
      try{JSONObject request=new JSONObject(message.getData()); String id=request.getString("id"); try{dispatch(id,request.getString("method"),request.optJSONObject("args")==null?new JSONObject():request.getJSONObject("args"));}catch(Exception e){fail(id,e.getMessage());}}catch(Exception e){ /* Invalid messages have no authority. */ }
    });
    runtime=localWeb(RUNTIME,true); FrameLayout.LayoutParams tiny=new FrameLayout.LayoutParams(1,1);root.addView(runtime,tiny);runtime.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
    WebViewCompat.addWebMessageListener(runtime,"RuntimeNative",Collections.singleton(RUNTIME),(v,m,o,isMain,reply)->{
      if(!isMain || !RUNTIME.equals(o.toString()))return;
      try{JSONObject data=new JSONObject(m.getData());String type=data.optString("type");if(type.equals("ready")){runtimeReady=true;event("runtimeReady",new JSONObject());return;}
        if(runID==null || !runID.equals(data.optString("jobID")))return;
        if(type.equals("phase")||type.equals("result")){if(data.toString().length()>150000)return;event("runtime",data);if(type.equals("result")){runID=null;getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);}}
      }catch(Exception e){}
    });
    runtime.loadUrl(RUNTIME+"/assets/Runtime/index.html");ui.loadUrl(APP+"/assets/web/index.html");
    if(Build.VERSION.SDK_INT>=33)getOnBackInvokedDispatcher().registerOnBackInvokedCallback(0,()->back());
  }
  private WebView localWeb(String origin,boolean execution){
    WebView view=new WebView(this);WebSettings s=view.getSettings();s.setJavaScriptEnabled(true);s.setDomStorageEnabled(false);s.setAllowFileAccess(false);s.setAllowContentAccess(false);s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);s.setTextZoom(Math.round(getResources().getConfiguration().fontScale*100));
    WebViewAssetLoader loader=new WebViewAssetLoader.Builder().setDomain(Uri.parse(origin).getHost()).addPathHandler("/assets/",new WebViewAssetLoader.AssetsPathHandler(this)).build();
    if(!execution)view.setWebChromeClient(new WebChromeClient(){
      @Override public boolean onJsConfirm(WebView v,String url,String message,JsResult result){new AlertDialog.Builder(MainActivity.this).setMessage(message).setPositiveButton("继续",(d,w)->result.confirm()).setNegativeButton("取消",(d,w)->result.cancel()).setOnCancelListener(d->result.cancel()).show();return true;}
    });
    view.setWebViewClient(new WebViewClient(){
      @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){if(r.isForMainFrame()&&!r.getUrl().toString().startsWith(origin+"/assets/")){if(!execution)openOfficial(r.getUrl().toString());return true;}return false;}
      @Override public WebResourceResponse shouldInterceptRequest(WebView v,WebResourceRequest r){
        // Resolve packaged assets before the external-image path: the asset host is
        // intentionally HTTPS too, but its scripts/styles must never hit the network.
        if(!r.getUrl().toString().startsWith(origin+"/assets/")){
          if(!execution && !r.isForMainFrame() && isPublicImage(r.getUrl()))return articleImage(r.getUrl());
          return new WebResourceResponse("text/plain","UTF-8",403,"Blocked",Collections.emptyMap(),new ByteArrayInputStream(new byte[0]));
        }
        WebResourceResponse response=loader.shouldInterceptRequest(r.getUrl());
        if(response!=null){Map<String,String> headers=new HashMap<>();headers.put("Content-Security-Policy",execution?"default-src 'none'; script-src 'self' 'unsafe-eval' 'wasm-unsafe-eval'; worker-src 'self'; connect-src 'self'; object-src 'none'; frame-src 'none'":"default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' https:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'");headers.put("X-Content-Type-Options","nosniff");response.setResponseHeaders(headers);}return response;
      }
      @Override public boolean onRenderProcessGone(WebView v,RenderProcessGoneDetail detail){if(execution){runtimeReady=false;if(runID!=null){event("runtime",json("type","result","jobID",runID,"status","resource-error","stdout","","stderr","系统终止了运行环境，请重新打开 App 后重试。","durationMS",0));runID=null;}}else Toast.makeText(MainActivity.this,"界面进程已退出，请重新打开 App；已保存记录仍保留。",Toast.LENGTH_LONG).show();return true;}
    });
    view.setBackgroundColor(Color.TRANSPARENT);return view;
  }
  private static boolean isPublicImage(Uri url){
    String host=url.getHost();
    return "https".equals(url.getScheme())&&url.getUserInfo()==null&&(url.getPort()==-1||url.getPort()==443)&&host!=null&&host.matches("(?i)(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,63}")&&!host.matches("(?i).*\\.(localhost|local|internal|lan|home|test|invalid)");
  }
  private WebResourceResponse articleImage(Uri url){
    HttpURLConnection c=null;
    try{
      for(int redirects=0;redirects<=5;redirects++){
        if(!isPublicImage(url))throw new IOException();
        for(java.net.InetAddress ip:java.net.InetAddress.getAllByName(url.getHost()))if(ip.isAnyLocalAddress()||ip.isLoopbackAddress()||ip.isLinkLocalAddress()||ip.isSiteLocalAddress()||ip.isMulticastAddress())throw new IOException();
        c=(HttpURLConnection)new URL(url.toString()).openConnection();c.setConnectTimeout(12000);c.setReadTimeout(15000);c.setInstanceFollowRedirects(false);c.setRequestProperty("Accept","image/avif,image/webp,image/*;q=0.9,*/*;q=0.1");
        int status=c.getResponseCode();
        if(status>=300&&status<400){String location=c.getHeaderField("Location");if(location==null)throw new IOException();url=Uri.parse(new URL(new URL(url.toString()),location).toString());c.disconnect();c=null;continue;}
        String type=c.getContentType();if(status!=200||type==null||!type.toLowerCase(Locale.ROOT).startsWith("image/"))throw new IOException();
        if(c.getContentLengthLong()>8*1024*1024)throw new IOException();
        ByteArrayOutputStream out=new ByteArrayOutputStream();try(InputStream in=c.getInputStream()){byte[] b=new byte[8192];int n;while((n=in.read(b))!=-1){if(out.size()+n>8*1024*1024)throw new IOException();out.write(b,0,n);}}
        return new WebResourceResponse(type.split(";")[0],null,200,"OK",Collections.singletonMap("X-Content-Type-Options","nosniff"),new ByteArrayInputStream(out.toByteArray()));
      }
      throw new IOException();
    }catch(Exception e){return new WebResourceResponse("text/plain","UTF-8",404,"Unavailable",Collections.emptyMap(),new ByteArrayInputStream(new byte[0]));}finally{if(c!=null)c.disconnect();}
  }
  private void dispatch(String id,String method,JSONObject args)throws Exception{
    switch(method){
      case "load": files.execute(()->{try{String text="";if(stateFile.getBaseFile().exists())try(InputStream in=stateFile.openRead()){text=read(in,24*1024*1024);}ok(id,json("state",text,"keyPresent",prefs.contains("keyCipher"),"folderLinked",prefs.contains("tree"),"runtimeReady",runtimeReady,"dark",isDark()));}catch(Exception e){fail(id,"本地数据读取失败，原文件保留。"+e.getMessage());}});break;
      case "save": {String text=args.getString("text");if(text.length()>24*1024*1024)throw new Exception("存档过大，请先导出备份。");new JSONObject(text);files.execute(()->{FileOutputStream out=null;try{out=stateFile.startWrite();out.write(text.getBytes(StandardCharsets.UTF_8));stateFile.finishWrite(out);ok(id,json("saved",true));}catch(Exception e){if(out!=null)stateFile.failWrite(out);fail(id,"保存失败，上一版仍保留。");}});break;}
      case "luoguCacheLoad": files.execute(()->{try{AtomicFile cache=new AtomicFile(new File(getFilesDir(),"luogu-cache.json"));String text="";if(cache.getBaseFile().exists())try(InputStream in=cache.openRead()){text=read(in,8*1024*1024);}ok(id,json("text",text));}catch(Exception e){fail(id,"离线题解缓存无法读取，草稿和训练记录不受影响。");}});break;
      case "luoguCacheSave": {String text=args.getString("text");if(text.getBytes(StandardCharsets.UTF_8).length>8*1024*1024)throw new Exception("离线题解超过8 MB，未覆盖旧缓存；草稿和训练记录不受影响。");new JSONObject(text);files.execute(()->{AtomicFile cache=new AtomicFile(new File(getFilesDir(),"luogu-cache.json"));FileOutputStream out=null;try{out=cache.startWrite();out.write(text.getBytes(StandardCharsets.UTF_8));cache.finishWrite(out);ok(id,json("saved",true));}catch(Exception e){if(out!=null)cache.failWrite(out);fail(id,"题解缓存保存失败，原缓存仍保留。");}});break;}
      case "luogu": { if(luogu==null)luogu=new LuoguSession(this,root,()->event("luoguReturned",new JSONObject())); luogu.read(args.getString("path"),(text,error)->{if(error!=null)fail(id,error);else ok(id,json("text",text));}); break; }
      case "luoguLogin": { if(luogu==null)luogu=new LuoguSession(this,root,()->event("luoguReturned",new JSONObject())); luogu.login();ok(id,json("opened",true));break; }
      case "luoguSource": {Uri u=Uri.parse(args.getString("url"));if(!"https".equals(u.getScheme())||!"www.luogu.com.cn".equals(u.getHost())||u.getUserInfo()!=null)throw new Exception("无效来源链接。");startActivity(new Intent(Intent.ACTION_VIEW,u));ok(id,json("opened",true));break;}
      case "get": {String url=args.getString("url");checkCF(url);network.execute(()->{try{ok(id,json("text",http(url,null,null,12*1024*1024)));}catch(Exception e){fail(id,e.getMessage());}});break;}
      case "key": {String key=args.optString("value").trim();if(key.isEmpty())prefs.edit().remove("keyCipher").remove("keyIV").apply();else storeKey(key);ok(id,json("keyPresent",!key.isEmpty()));break;}
      case "ai": network.execute(()->{try{String key=loadKey();if(key.isEmpty())throw new Exception("请先在设置中填写自己的 DeepSeek API Key。");String model=args.optString("model","deepseek-chat");if(!model.equals("deepseek-chat")&&!model.equals("deepseek-reasoner"))throw new Exception("不支持这个模型。");JSONObject body=json("model",model,"messages",args.getJSONArray("messages"),"stream",false,"max_tokens",8192);ok(id,json("text",http("https://api.deepseek.com/chat/completions",body.toString(),key,2*1024*1024)));}catch(Exception e){fail(id,e.getMessage());}});break;
      case "run": {if(!runtimeReady)throw new Exception("本地运行环境尚未就绪，请稍后重试。");if(runID!=null)throw new Exception("已有运行任务。");if(args.getString("source").getBytes(StandardCharsets.UTF_8).length>262144||args.optString("stdin").getBytes(StandardCharsets.UTF_8).length>65536)throw new Exception("代码上限256KB，输入上限64KB。");String lang=args.getString("language");if(!lang.equals("C++")&&!lang.equals("Python"))throw new Exception("语言不支持。");runID=args.getString("id");getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);runtime.evaluateJavascript("window.startJob("+args+");",null);ok(id,json("started",true));break;}
      case "stop": stopRuntime();ok(id,json("stopped",true));break;
      case "browser": {String url=args.getString("url");boolean reload=args.optBoolean("reload")&&official!=null&&url.equals(official.getUrl());openOfficial(url);if(reload)official.reload();ok(id,json("opened",true));break;}
      case "cfInspect": ensureOfficial();evalOfficial(id,"const input="+args+";return "+asset("cf-snapshot.js")+";");break;
      case "cfSubmit": ensureOfficial();evalOfficial(id,"const input="+args+";\n"+asset("cf-dispatch.js"));break;
      case "cfReceipt": ensureOfficial();evalOfficial(id,"const input="+args+";\n"+asset("cf-receipt.js"));break;
      case "import": startPicker(id,"import",null);break;
      case "export": startPicker(id,"export",args.getString("text"));break;
      case "folder": startPicker(id,"folder",null);break;
      case "folderAccept": previousTree=null;prefs.edit().remove("pendingTreePrevious").apply();ok(id,json("accepted",true));break;
      case "folderCancel": if(prefs.contains("pendingTreePrevious")){String old=prefs.getString("pendingTreePrevious","");if(old.isEmpty())prefs.edit().remove("tree").remove("pendingTreePrevious").commit();else prefs.edit().putString("tree",old).remove("pendingTreePrevious").commit();}previousTree=null;ok(id,json("cancelled",true));break;
      case "folderRead": files.execute(()->{try{ok(id,readFolder());}catch(Exception e){fail(id,e.getMessage());}});break;
      case "folderWrite": files.execute(()->{try{writeFolder(args.getJSONArray("changes"));ok(id,json("saved",true));}catch(Exception e){fail(id,e.getMessage());}});break;
      case "unlink": prefs.edit().remove("tree").apply();ok(id,json("unlinked",true));break;
      case "exit": finish();break;
      case "copy": ((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("CF Pocket",args.getString("text")));ok(id,json("copied",true));break;
      default: throw new Exception("不支持的操作。");
    }
  }
  private static JSONObject json(Object... fields){JSONObject o=new JSONObject();try{for(int i=0;i<fields.length;i+=2)o.put((String)fields[i],fields[i+1]);}catch(Exception e){throw new IllegalArgumentException(e);}return o;}
  private void ok(String id,Object value){deliver(json("id",id,"result",value));}
  private void fail(String id,String message){deliver(json("id",id,"error",message==null?"操作失败，请重试。":message));}
  private void deliver(JSONObject value){main.post(()->{if(!closing)ui.evaluateJavascript("window.nativeReply&&window.nativeReply("+value+");",null);});}
  private void event(String name,JSONObject data){main.post(()->{if(!closing)ui.evaluateJavascript("window.nativeEvent&&window.nativeEvent("+JSONObject.quote(name)+","+data+");",null);});}
  private static String read(InputStream in,int cap)throws Exception{ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[32768];int n;while((n=in.read(b))!=-1){if(out.size()+n>cap)throw new IOException("内容过大，已停止读取。");out.write(b,0,n);}return out.toString("UTF-8");}
  private static void checkCF(String url)throws Exception{URI u=new URI(url);if(!"https".equals(u.getScheme())||!"codeforces.com".equals(u.getHost())||u.getUserInfo()!=null||(u.getPort()!=-1&&u.getPort()!=443))throw new Exception("只允许访问 Codeforces 官方 HTTPS 页面。");}
  private static String http(String url,String post,String key,int cap)throws Exception{
    HttpURLConnection c=(HttpURLConnection)new URL(url).openConnection();c.setConnectTimeout(20000);c.setReadTimeout(post==null?30000:180000);c.setInstanceFollowRedirects(false);c.setRequestProperty("User-Agent","CFPocketAndroid/0.1 (+personal learning app)");
    try{if(post!=null){c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");c.setRequestProperty("Authorization","Bearer "+key);try(OutputStream out=c.getOutputStream()){out.write(post.getBytes(StandardCharsets.UTF_8));}}
      int code=c.getResponseCode();if(code!=200){if(code==401)throw new Exception("API Key 无效或已失效，请检查设置。");if(code==402)throw new Exception("API 余额不足。");if(code==429)throw new Exception("请求过于频繁，请稍后重试。");throw new Exception(code==403?"网站要求验证，请在 App 内打开官网后读取页面。":"网络请求失败（"+code+"），已有内容仍保留。");}
      try(InputStream in=c.getInputStream()){return read(in,cap);}
    }finally{c.disconnect();}
  }
  private SecretKey secretKey()throws Exception{KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);if(ks.containsAlias("CFPocketAI"))return (SecretKey)ks.getKey("CFPocketAI",null);KeyGenerator gen=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");gen.init(new KeyGenParameterSpec.Builder("CFPocketAI",KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());return gen.generateKey();}
  private void storeKey(String text)throws Exception{if(text.length()>1024)throw new Exception("Key 格式异常。");Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,secretKey());prefs.edit().putString("keyCipher",Base64.getEncoder().encodeToString(c.doFinal(text.getBytes(StandardCharsets.UTF_8)))).putString("keyIV",Base64.getEncoder().encodeToString(c.getIV())).apply();}
  private String loadKey()throws Exception{if(!prefs.contains("keyCipher"))return "";Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,secretKey(),new GCMParameterSpec(128,Base64.getDecoder().decode(prefs.getString("keyIV",""))));return new String(c.doFinal(Base64.getDecoder().decode(prefs.getString("keyCipher",""))),StandardCharsets.UTF_8);}
  private String asset(String name)throws Exception{try(InputStream in=getAssets().open("web/"+name)){return read(in,1024*1024);}}
  private void ensureOfficial()throws Exception{if(official==null||official.getUrl()==null)throw new Exception("请先打开官网并登录。");checkCF(official.getUrl());}
  private void openOfficial(String url){try{checkCF(url);}catch(Exception e){Toast.makeText(this,"仅支持 Codeforces 官方链接",Toast.LENGTH_SHORT).show();return;}
    if(official==null){official=new WebView(this);official.getSettings().setJavaScriptEnabled(true);official.getSettings().setDomStorageEnabled(true);official.getSettings().setAllowFileAccess(false);official.getSettings().setAllowContentAccess(false);official.getSettings().setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);android.webkit.CookieManager.getInstance().setAcceptCookie(true);android.webkit.CookieManager.getInstance().setAcceptThirdPartyCookies(official,false);
      official.setWebViewClient(new WebViewClient(){@Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest req){if(!req.isForMainFrame())return false;try{checkCF(req.getUrl().toString());return false;}catch(Exception e){return true;}}@Override public void onPageFinished(WebView v,String u){event("browserLoaded",json("url",u));}});
      browserPane=new LinearLayout(this);browserPane.setOrientation(LinearLayout.VERTICAL);browserPane.setBackgroundColor(isDark()?Color.rgb(14,24,30):Color.WHITE);LinearLayout bar=new LinearLayout(this);String[] titles={"返回 App","读取题面","刷新"};for(String title:titles){Button b=new Button(this);b.setText(title);bar.addView(b,new LinearLayout.LayoutParams(0,56*getResources().getDisplayMetrics().densityDpi/160,1));b.setOnClickListener(v->{if(title.equals("返回 App")){browserPane.setVisibility(View.GONE);event("browserClosed",new JSONObject());}else if(title.equals("刷新"))official.reload();else official.evaluateJavascript("JSON.stringify({url:location.href,html:document.documentElement.outerHTML})",value->{try{String text=(String)new JSONTokener(value).nextValue();JSONObject data=new JSONObject(text);checkCF(data.getString("url"));if(text.length()>5*1024*1024)throw new Exception("页面过大");event("capturedPage",data);browserPane.setVisibility(View.GONE);}catch(Exception e){Toast.makeText(this,"页面尚未准备好",Toast.LENGTH_SHORT).show();}});});}browserPane.addView(bar);browserPane.addView(official,new LinearLayout.LayoutParams(-1,0,1));root.addView(browserPane,new FrameLayout.LayoutParams(-1,-1));}
    browserPane.setVisibility(View.VISIBLE);browserPane.bringToFront();if(!url.equals(official.getUrl()))official.loadUrl(url);
  }
  private void evalOfficial(String id,String body){String token=UUID.randomUUID().toString();String access="window.__pocketOps["+JSONObject.quote(token)+"]";official.evaluateJavascript("window.__pocketOps=window.__pocketOps||{};(async()=>{"+body+"})().then(r=>{"+access+"={result:r}}).catch(e=>{"+access+"={error:String(e.message||e)}});",v->pollOfficial(id,token,0));}
  private void pollOfficial(String id,String token,int count){if(count>120){fail(id,"官网响应超时，发送状态未确认；不会自动重发。");return;}official.evaluateJavascript("JSON.stringify(window.__pocketOps?.["+JSONObject.quote(token)+"]||null)",v->{try{Object raw=new JSONTokener(v).nextValue();if(!(raw instanceof String)||raw.equals("null")){main.postDelayed(()->pollOfficial(id,token,count+1),250);return;}JSONObject r=new JSONObject((String)raw);if(r.has("error"))fail(id,r.getString("error"));else ok(id,r.opt("result"));official.evaluateJavascript("delete window.__pocketOps?.["+JSONObject.quote(token)+"]",null);}catch(Exception e){main.postDelayed(()->pollOfficial(id,token,count+1),250);}});}
  private void startPicker(String id,String mode,String text)throws Exception{if(pickerID!=null)throw new Exception("文件选择器已打开。");pickerID=id;pickerMode=mode;exportText=text;Intent intent;if(mode.equals("folder"))intent=new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);else if(mode.equals("export"))intent=new Intent(Intent.ACTION_CREATE_DOCUMENT).setType("application/json").putExtra(Intent.EXTRA_TITLE,"CFPocket-备份.json").addCategory(Intent.CATEGORY_OPENABLE);else intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE);startActivityForResult(intent,100);}
  @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request!=100||pickerID==null)return;String id=pickerID,mode=pickerMode,text=exportText;pickerID=null;pickerMode=null;exportText=null;if(result!=RESULT_OK||data==null||data.getData()==null){fail(id,"已取消选择");return;}Uri uri=data.getData();files.execute(()->{try{if(mode.equals("folder")){int flags=data.getFlags()&(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);if(flags!=(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION))throw new IOException("这个文件提供方未授予读写权限，请选择可写的题单文件夹。");getContentResolver().takePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);String previous=prefs.getString("tree",null);previousTree=previous;prefs.edit().putString("pendingTreePrevious",previous==null?"":previous).putString("tree",uri.toString()).commit();try{ok(id,readFolder());}catch(Exception e){if(previous==null)prefs.edit().remove("tree").commit();else prefs.edit().putString("tree",previous).commit();throw e;}}else if(mode.equals("export")){try(OutputStream out=getContentResolver().openOutputStream(uri,"wt")){if(out==null)throw new IOException("无法写入文件");out.write(text.getBytes(StandardCharsets.UTF_8));}ok(id,json("exported",true));}else try(InputStream in=getContentResolver().openInputStream(uri)){if(in==null)throw new IOException("无法读取文件");ok(id,json("text",read(in,24*1024*1024)));}}catch(Exception e){fail(id,e.getMessage());}});}
  private DocumentFile folder()throws Exception{String uri=prefs.getString("tree",null);if(uri==null)throw new Exception("请先关联题单文件夹。");DocumentFile f=DocumentFile.fromTreeUri(this,Uri.parse(uri));if(f==null||!f.exists()||!f.canRead())throw new Exception("文件夹权限失效，请重新关联。");return f;}
  private JSONObject readFolder()throws Exception{DocumentFile f=folder(),cf=f.findFile("cf"),overview=f.findFile("训练总览.md");if(cf==null||!cf.isDirectory()||overview==null)throw new Exception("请选择含训练总览.md和cf目录的完整题单文件夹。");JSONObject result=new JSONObject();result.put("训练总览.md",docText(overview));for(char ch='A';ch<='Z';ch++){String name=ch+".md";DocumentFile file=cf.findFile(name);if(file==null)throw new Exception("题单缺少 cf/"+name+"，未改动原进度。");result.put("cf/"+name,docText(file));}return json("files",result,"name",f.getName());}
  private String docText(DocumentFile f)throws Exception{if(!f.isFile())throw new Exception("不是普通文件。");try(InputStream in=getContentResolver().openInputStream(f.getUri())){if(in==null)throw new IOException("文件不可读");return read(in,1024*1024);}}
  private void writeFolder(JSONArray changes)throws Exception{
    if(changes.length()>27)throw new Exception("写入文件数量异常。");DocumentFile root=folder(),cf=root.findFile("cf");List<DocumentFile> targets=new ArrayList<>();Set<String> seen=new HashSet<>();
    for(int i=0;i<changes.length();i++){JSONObject change=changes.getJSONObject(i);String path=change.getString("path");if(!path.equals("训练总览.md")&&!path.matches("cf/[A-Z]\\.md"))throw new Exception("无效题单路径。");if(!seen.add(path))throw new Exception("重复文件。");DocumentFile target=path.startsWith("cf/")?cf.findFile(path.substring(3)):root.findFile(path);if(target==null||!target.canWrite()||!docText(target).equals(change.getString("before")))throw new Exception("文件刚被其它应用修改，已保留本机进度，请重新同步。");if(change.getString("after").length()>1024*1024)throw new Exception("文件过大。");targets.add(target);}
    File backup=new File(getFilesDir(),"plan-backups/"+System.currentTimeMillis());backup.mkdirs();
    for(int i=0;i<changes.length();i++){JSONObject change=changes.getJSONObject(i);try(FileOutputStream out=new FileOutputStream(new File(backup,change.getString("path").replace('/','_')))){out.write(change.getString("before").getBytes(StandardCharsets.UTF_8));}}
    for(int i=0;i<changes.length();i++){JSONObject change=changes.getJSONObject(i);DocumentFile target=targets.get(i);if(!docText(target).equals(change.getString("before")))throw new Exception("文件同步期间发生变化，待写回进度已保留。");try(OutputStream out=getContentResolver().openOutputStream(target.getUri(),"wt")){if(out==null)throw new IOException("文件不可写");out.write(change.getString("after").getBytes(StandardCharsets.UTF_8));}if(!docText(target).equals(change.getString("after")))throw new Exception("写回核对未通过，请重试；写入前备份保存在App内。");}
  }
  private boolean isDark(){return (getResources().getConfiguration().uiMode & android.content.res.Configuration.UI_MODE_NIGHT_MASK)==android.content.res.Configuration.UI_MODE_NIGHT_YES;}
  private void applyAppearance(){boolean dark=isDark();root.setBackgroundColor(dark?Color.rgb(14,24,30):Color.rgb(242,245,240));getWindow().getDecorView().setSystemUiVisibility(dark?0:View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);if(ui!=null){ui.getSettings().setTextZoom(Math.round(getResources().getConfiguration().fontScale*100));event("appearance",json("dark",dark));}}
  @Override public void onConfigurationChanged(android.content.res.Configuration configuration){super.onConfigurationChanged(configuration);applyAppearance();}
  private void stopRuntime(){if(runtime!=null)runtime.evaluateJavascript("window.stopJob&&window.stopJob('已停止本地运行');",null);}
  private void back(){if(luogu!=null&&luogu.visible()){luogu.hide();}else if(browserPane!=null&&browserPane.getVisibility()==View.VISIBLE){browserPane.setVisibility(View.GONE);event("browserClosed",new JSONObject());}else ui.evaluateJavascript("window.appBack&&window.appBack()",null);}
  @Override public void onBackPressed(){back();}
  @Override protected void onStop(){super.onStop();stopRuntime();if(ui!=null)ui.evaluateJavascript("window.appBackground&&window.appBackground()",null);}
  @Override protected void onDestroy(){closing=true;stopRuntime();if(ui!=null)ui.destroy();if(runtime!=null)runtime.destroy();if(official!=null)official.destroy();if(luogu!=null)luogu.destroy();files.shutdown();network.shutdownNow();super.onDestroy();}
}
