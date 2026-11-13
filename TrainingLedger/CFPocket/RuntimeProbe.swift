import Foundation
import PocketCore

@MainActor enum RuntimeProbe {
  struct Case: Codable { let name:String;let language:CodeLanguage;let source:String;let input:String;let expected:String?;let expectedStatus:String;var stop=false;var standard="c++20" }
  struct Result:Codable{let name:String;let expectedStatus:String;let passed:Bool;let run:LocalRun}
  static func run(engine:RuntimeEngine) async {
    engine.prepare()
    let until=Date().addingTimeInterval(30)
    while !engine.ready && Date()<until {try? await Task.sleep(for:.milliseconds(100))}
    guard engine.ready else {write(["error":"Runtime not ready", "time":Date().description]);return}
    let cases:[Case]=[
      Case(name:"cpp20-stdin-ranges-STL",language:.cpp,source:"#include <iostream>\n#include <vector>\n#include <algorithm>\nint main(){int n;std::cin>>n;std::vector<int>a(n);for(auto &x:a)std::cin>>x;std::ranges::sort(a);for(auto x:a)std::cout<<x<<' ';}",input:"3\n9 1 4\n",expected:"1 4 9",expectedStatus:"ok"),
      Case(name:"cpp17-bits-int128",language:.cpp,source:"#include <bits/stdc++.h>\nusing namespace std;int main(){long long x;cin>>x;__int128 y=(__int128)x*x;vector<int>a{3,1};sort(a.begin(),a.end());cout<<(long long)(y%1000000007)<<' '<<a[0];}",input:"1000000000\n",expected:"49 1",expectedStatus:"ok",standard:"c++17"),
      Case(name:"cpp-version-stdio-format",language:.cpp,source:"#include <cstdio>\nint main(){printf(\"%d %d %d %ld %lu %lu\",__clang_major__,__clang_minor__,__clang_patchlevel__,__cplusplus,sizeof(long long),sizeof(__int128));}",input:"",expected:"22 1 8 202002 8 16",expectedStatus:"ok"),
      Case(name:"cpp-syntax-error",language:.cpp,source:"int main(){ this is not C++; }",input:"",expected:nil,expectedStatus:"compile-error"),
      Case(name:"cpp-PBDS-unsupported",language:.cpp,source:"#include <ext/pb_ds/assoc_container.hpp>\nint main(){}",input:"",expected:nil,expectedStatus:"unsupported-feature"),
      Case(name:"cpp-runtime-trap",language:.cpp,source:"int main(){__builtin_trap();}",input:"",expected:nil,expectedStatus:"runtime-error"),
      Case(name:"cpp-memory-cap",language:.cpp,source:"#include <cstdlib>\n#include <cstdio>\nint main(){volatile unsigned char*p=(volatile unsigned char*)malloc(300*1024*1024);if(p){p[0]=1;p[300*1024*1024-1]=2;}puts(p?\"allocated\":\"limited\");}",input:"",expected:"limited",expectedStatus:"ok"),
      Case(name:"cpp-containers-recursion-array",language:.cpp,source:"#include <bits/stdc++.h>\nusing namespace std;long long fact(int n){return n<2?1:n*fact(n-1);}int main(){map<int,int>m;m[3]=7;queue<int>q;q.push(4);vector<int>a(100000);iota(a.begin(),a.end(),0);cout<<fact(10)<<' '<<m[3]<<' '<<q.front()<<' '<<a.back();}",input:"",expected:"3628800 7 4 99999",expectedStatus:"ok"),
      Case(name:"cpp-recursion-overflow",language:.cpp,source:"__attribute__((optnone)) int f(int n){volatile char pad[4096];pad[0]=(char)n;return f(n+1)+pad[0];}int main(){return f(0);}",input:"",expected:nil,expectedStatus:"runtime-error"),
      Case(name:"cpp-timeout",language:.cpp,source:"int main(){volatile unsigned x=0;for(;;)++x;}",input:"",expected:nil,expectedStatus:"timeout"),
      Case(name:"cpp-stop",language:.cpp,source:"int main(){volatile unsigned x=0;for(;;)++x;}",input:"",expected:nil,expectedStatus:"stopped",stop:true),
      Case(name:"cpp-output-cap",language:.cpp,source:"#include <cstdio>\nint main(){for(int i=0;i<100000;i++)puts(\"abcdefghi\");}",input:"",expected:nil,expectedStatus:"output-limit"),
      Case(name:"python-stdin-stdlib",language:.python,source:"import sys, math, statistics\nfrom collections import deque\na=list(map(int,sys.stdin.read().split()))\nprint(sum(a),math.isqrt(81),len(deque(a)))",input:"1 2 3\n",expected:"6 9 3",expectedStatus:"ok"),
      Case(name:"python-syntax-error",language:.python,source:"def broken(:\n pass",input:"",expected:nil,expectedStatus:"runtime-error"),
      Case(name:"python-exception",language:.python,source:"print(1//0)",input:"",expected:nil,expectedStatus:"runtime-error"),
      Case(name:"python-recursion-overflow",language:.python,source:"def f():\n return f()\nf()",input:"",expected:nil,expectedStatus:"runtime-error"),
      Case(name:"python-timeout",language:.python,source:"while True:\n pass",input:"",expected:nil,expectedStatus:"timeout"),
      Case(name:"python-stop",language:.python,source:"while True:\n pass",input:"",expected:nil,expectedStatus:"stopped",stop:true),
      Case(name:"python-output-cap",language:.python,source:"print('x'*100000)",input:"",expected:nil,expectedStatus:"output-limit"),
      Case(name:"python-stdin-empty-exact",language:.python,source:"import sys\nprint(repr(sys.stdin.read()))",input:"",expected:"''",expectedStatus:"ok"),
      Case(name:"python-stdin-no-added-newline",language:.python,source:"import sys\nprint(repr(sys.stdin.read()))",input:"abc",expected:"'abc'",expectedStatus:"ok"),
      Case(name:"python-unicode-stdin",language:.python,source:"import sys\nprint(repr(sys.stdin.read()))",input:"你好\n",expected:"'你好\\n'",expectedStatus:"ok"),
      Case(name:"cpp-unicode-stdin",language:.cpp,source:"#include <iostream>\n#include <string>\nint main(){std::string s;std::cin>>s;std::cout<<s;}",input:"你好\n",expected:"你好",expectedStatus:"ok"),
      Case(name:"python-network-blocked",language:.python,source:"from pyodide.http import open_url\nopen_url('https://example.com')",input:"",expected:nil,expectedStatus:"runtime-error"),
      Case(name:"python-cannot-reset-deadline",language:.python,source:"import time\nfrom js import JSON, postMessage\nmessage=JSON.parse('{\"type\":\"phase\",\"phase\":\"run\"}')\ninvalid=JSON.parse('{\"type\":\"phase\",\"phase\":\"__proto__\"}')\nnext_at=0\nwhile True:\n if time.monotonic() >= next_at:\n  postMessage(invalid)\n  postMessage(message)\n  next_at=time.monotonic()+0.2",input:"",expected:nil,expectedStatus:"timeout"),
      Case(name:"python-forged-large-result-bounded",language:.python,source:"from js import JSON,postMessage\npostMessage(JSON.parse('{\"type\":\"result\",\"status\":\"ok\",\"stdout\":\"'+'x'*70000+'\"}'))\nwhile True:\n pass",input:"",expected:nil,expectedStatus:"output-limit"),
      Case(name:"python-control-message-flood",language:.python,source:"from js import JSON,postMessage\nm=JSON.parse('{\"type\":\"unexpected-message\"}')\nwhile True:\n postMessage(m)",input:"",expected:nil,expectedStatus:"message-limit"),
      Case(name:"python-isolation-write",language:.python,source:"open('/tmp/cfpocket-proof','w').write('secret')\nprint('written')",input:"",expected:"written",expectedStatus:"ok"),
      Case(name:"python-isolation-read",language:.python,source:"import os\nprint(os.path.exists('/tmp/cfpocket-proof'))",input:"",expected:"False",expectedStatus:"ok")
    ]
    var results:[Result]=[]
    for item in cases {
      guard engine.inForeground else { engine.completion = nil; write(["error":"Self-check paused because app left foreground"]); return }
      // A prior stress case can terminate WebKit; wait for its new local document handshake.
      let readyDeadline = Date().addingTimeInterval(35)
      engine.prepare()
      while !engine.ready && Date() < readyDeadline { try? await Task.sleep(for: .milliseconds(100)) }
      guard engine.ready else { write(["error": "Runtime did not recover", "case": item.name]); return }
      var captured:LocalRun?
      engine.completion={captured=$0}
      engine.run(revision:CodeRevision(source:item.source,language:item.language),input:item.input,expected:item.expected,standard:item.standard)
      let deadline=Date().addingTimeInterval(105)
      var stopped=false
      while captured == nil && Date()<deadline {
        try? await Task.sleep(for:.milliseconds(100))
        if item.stop && engine.phase == "本地执行" && !stopped {stopped=true;try? await Task.sleep(for:.milliseconds(150));engine.stop()}
      }
      if let value=captured {
        results.append(Result(name:item.name,expectedStatus:item.expectedStatus,passed:value.status==item.expectedStatus && (item.expected==nil || value.textMatches==true),run:value))
        persist(results, name: "runtime-probe-progress.json")
        print("CFPOCKET_PROBE \(item.name) \(value.status) pass=\(results.last!.passed)")
      }else{write(["error":"Probe timed out", "case":item.name]);return}
    }
    engine.completion=nil
    persist(results, name: "runtime-probe.json")
  }
  private static func persist(_ results: [Result], name: String) {
    let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601;encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
    if let data=try? encoder.encode(results){try? data.write(to:URL.documentsDirectory.appendingPathComponent(name),options:.atomic)}
  }
  private static func write(_ data:[String:String]){try? JSONSerialization.data(withJSONObject:data,options:.prettyPrinted).write(to:URL.documentsDirectory.appendingPathComponent("runtime-probe-error.json"),options:.atomic)}
}
