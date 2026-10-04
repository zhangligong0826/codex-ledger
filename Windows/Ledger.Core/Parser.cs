using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
namespace CodexLedger;
public static class Classifier {
    public static string Clean(string text) {
        var v=text.Trim();if(v.StartsWith("# Selected text:")||v.StartsWith("# Response annotations:")||v.StartsWith("# Files mentioned by the user:")) {
            int pos=v.IndexOf("## My request:",StringComparison.Ordinal);if(pos>=0){var comments=new List<string>();var a=Regex.Match(v,@"<response-annotations>([\s\S]*?)</response-annotations>");if(a.Success)try{using var d=JsonDocument.Parse(a.Groups[1].Value);comments.AddRange(d.RootElement.Items().Select(x=>x.S("annotation")).Where(x=>x.Length>0));}catch(JsonException){}v=string.Join("\n",comments.Append(v[(pos+14)..]));}
        }
        var h=Regex.Match(v,@"<heartbeat>[\s\S]*?<instructions>([\s\S]*?)</instructions>");if(h.Success)v="定时任务："+h.Groups[1].Value;
        return Regex.Replace(v,@"<(environment_context|external_codex_apps_open_page|external_context|system_reminder|image)(?:\s[^>]*)?>[\s\S]*?</\1>","").Trim();
    }
    public static bool AssociatedFile(string path) {var p=path.Replace('\\','/');return !new[]{"/.codex/plugins/","/.codex/skills/","/.agents/skills/"}.Any(p.Contains)&&!(p.Contains("/Documents/Codex/")&&p.Contains("/work/"));}
    public static string Category(string prompt,IReadOnlyList<string> artifacts,string inherited="unknown",bool internalAgent=false) {
        if(internalAgent)return "background";var p=Clean(prompt).ToLowerInvariant();
        bool Has(params string[] terms)=>terms.Any(p.Contains);
        bool intent=Has("帮我","给我","制作","设计","生成","创建","完成","开发","实现","写一","做一","做个","做ppt","修改","改成","编辑","重写","转成","导出","排版","build ","create ","make ","generate ","implement ","fix ","write ","design ","convert ");
        bool explicitProduction=Has("帮我制作","帮我生成","帮我写","帮我完成","帮我开发","帮我实现","帮我创建","build ","create ","implement ","generate ");
        if(Has("有什么想法","有现成","是什么","有什么区别","怎么用","如何","怎么样","为什么","解释","讲解","举例","给我举","是否","what is","how do","explain ")&&!explicitProduction)return "question";
        var extensions=artifacts.Select(x=>Path.GetExtension(x).ToLowerInvariant()).ToHashSet();var outputs=new List<string>();
        if(extensions.Overlaps([".pptx",".ppt"]))outputs.Add("slides");if(extensions.Overlaps([".docx",".doc"]))outputs.Add("document");if(extensions.Overlaps([".xlsx",".xls",".csv",".tsv"]))outputs.Add("spreadsheet");if(outputs.Count==0&&extensions.Overlaps([".png",".jpg",".jpeg",".webp",".svg"])&&Has("图片","画","海报","image","logo"))outputs.Add("image");
        if(p.Length==0&&outputs.Count>0)return outputs.Count>1?"mixed":outputs[0];
        if(intent&&Has("mac应用","mac 应用","macos","插件","app","网站","程序","开发","重构"))return "coding";
        var targets=new List<string>();if(Has("ppt","powerpoint","幻灯片","演示文稿","slide deck","presentation"))targets.Add("slides");if(Has("word","docx","文档","写作","稿件","公文","写文章","撰写","改写文章","重写文章","写一篇"))targets.Add("document");if(Has("excel","xlsx","csv","表格","电子表","数据清洗"))targets.Add("spreadsheet");
        if(intent&&targets.Count>0)return targets.Count>1?"mixed":targets[0];
        if(Has("研究","调研","研报","论文","文献","财报","投资","分析","research","analyze","analysis"))return "research";
        if(Has("画一","绘制","生成图片","海报","logo","插画","image generation","draw "))return "image";
        if(Has("代码","报错","脚本","bug","debug","编程","swift","python","typescript"))return "coding";
        if(p.Length<25&&Has("继续","好的","可以","接着","continue","yes","go ahead")&&inherited!="unknown")return inherited;
        return p.Length==0?"unknown":"question";
    }
}
public sealed class LogParser {
    public ParsedLog Parse(string path) {
        var log=new ParsedLog{Path=path};string turn="initial",root="initial",model="未知模型",cwd="",lastPrompt="",previous="unknown";
        TokenUsage? cumulative=null;var legacy=new List<UsageSample>();var structured=new List<UsageSample>();var seen=new HashSet<string>();var oldSeen=new HashSet<string>();bool modern=false,before=false;long? ordinalStart=null;
        DateTimeOffset fallback=File.GetLastWriteTimeUtc(path);
        TurnInfo Ensure(string id,DateTimeOffset stamp,string? r=null) {if(!log.Turns.TryGetValue(id,out var info)){info=new(){ID=id,SessionID=log.SessionID,RootTurnID=r??root,Model=model,Start=stamp,WorkingDirectory=cwd,InheritedCategory=previous};log.Turns[id]=info;}return info;}
        void Artifacts(string text,string id) {if(!log.Turns.TryGetValue(id,out var info)||info.Artifacts.Count>=30)return;foreach(Match m in Regex.Matches(text[..Math.Min(text.Length,100000)],@"(?:[A-Za-z]:[\\/]|\\\\|/(?:Users|Volumes|private/tmp|tmp)/)[^\n<>""`\)\]\{\}]*?\.(?:pptx|docx|xlsx|csv|tsv|pdf|png|jpg|jpeg|webp|svg|md|html|swift|py|js|ts|app|zip|icns)(?=[\s""'`<>\)\],;]|$)",RegexOptions.IgnoreCase))if(!info.Artifacts.Contains(m.Value))info.Artifacts.Add(m.Value);}
        using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);
        using var reader=new StreamReader(stream);
        while(reader.ReadLine() is { } line) {
            if(string.IsNullOrWhiteSpace(line))continue;JsonDocument doc;
            try{doc=JsonDocument.Parse(line);}catch(JsonException){if(!reader.EndOfStream)log.Malformed++;continue;}
            using(doc) {
                var e=doc.RootElement;var type=e.S("type");var p=e.J("payload");if(type.Length==0||p.ValueKind!=JsonValueKind.Object){log.Malformed++;continue;}
                var stamp=DateTimeOffset.TryParse(e.S("timestamp"),CultureInfo.InvariantCulture,DateTimeStyles.RoundtripKind,out var dt)?dt:fallback;
                if(type=="session_meta") {
                    log.SessionID=p.S("id",p.S("session_id",Path.GetFileNameWithoutExtension(path)));cwd=p.S("cwd");log.WorkingDirectory=cwd;log.ParentID=p.S("parent_thread_id",p.S("forked_from_id"));
                    log.InternalAgent=p.J("source").J("subagent").ValueKind!=JsonValueKind.Undefined||p.S("thread_source")=="guardian_review";
                    ordinalStart=p.J("subagent_history_start_ordinal").ValueKind==JsonValueKind.Number?p.N("subagent_history_start_ordinal"):null;before=ordinalStart.HasValue;continue;
                }
                if(ordinalStart.HasValue&&e.J("ordinal").ValueKind==JsonValueKind.Number)before=e.N("ordinal")<ordinalStart.Value;
                if(type=="event_msg"&&p.S("type")=="task_started") {if(log.Turns.TryGetValue(turn,out var old))previous=Classifier.Category(old.Prompt,old.Artifacts,old.InheritedCategory);turn=p.S("turn_id","turn-"+(stamp-DateTimeOffset.UnixEpoch).TotalSeconds.ToString(CultureInfo.InvariantCulture));root=p.S("root_turn_id",turn);lastPrompt="";Ensure(turn,stamp);continue;}
                if(type=="turn_context") {turn=p.S("turn_id",turn);root=p.S("root_turn_id",turn);model=p.S("model",model);cwd=p.S("cwd",cwd);var i=Ensure(turn,stamp);i.Model=model;i.WorkingDirectory=cwd;if(i.Prompt.Length==0)i.Prompt=lastPrompt;continue;}
                if((type=="response_item"&&p.S("type")=="message"&&p.S("role")=="user")||(type=="event_msg"&&p.S("type")=="user_message")) {
                    string clean=Classifier.Clean(type=="event_msg"?p.S("message"):string.Join("\n",p.J("content").Items().Select(x=>x.S("text"))));
                    if(clean.Length>0){if(log.FirstPrompt.Length==0&&!before)log.FirstPrompt=clean[..Math.Min(200,clean.Length)];lastPrompt=clean[..Math.Min(1000,clean.Length)];var i=Ensure(turn,stamp);if(type=="event_msg"||i.Prompt.Length==0)i.Prompt=lastPrompt;}continue;
                }
                if(type=="token_usage_record"&&p.J("usage").ValueKind==JsonValueKind.Object) {
                    if(before||(p.S("thread_id").Length>0&&log.SessionID.Length>0&&p.S("thread_id")!=log.SessionID))continue;
                    string id=p.S("response_id",log.SessionID+":record:"+(e.J("ordinal").ValueKind==JsonValueKind.Number?e.N("ordinal").ToString(): (stamp-DateTimeOffset.UnixEpoch).TotalSeconds.ToString("0.0",CultureInfo.InvariantCulture)));
                    if(!seen.Add(id))continue;string t=p.S("turn_id",turn),r=p.S("root_turn_id",root);if(!log.Turns.ContainsKey(t)){var i=Ensure(t,stamp,r);i.Prompt=lastPrompt;}
                    structured.Add(new(id,log.SessionID,t,r,stamp,p.S("model",model),TokenUsage.Read(p.J("usage"))));modern=true;continue;
                }
                if(type=="event_msg"&&p.S("type")=="token_count"&&p.J("info").J("total_token_usage").ValueKind==JsonValueKind.Object) {
                    var info=p.J("info");var u=TokenUsage.Read(info.J("total_token_usage"));var delta=u.Delta(cumulative);cumulative=u;if(before||delta.Total==0)continue;
                    var signature=$"{log.SessionID}:{turn}:{(stamp-DateTimeOffset.UnixEpoch).TotalSeconds.ToString("0.0",CultureInfo.InvariantCulture)}:{u.Input}:{u.Output}";
                    if(!oldSeen.Add(signature))continue;Ensure(turn,stamp);legacy.Add(new(signature,log.SessionID,turn,root,stamp,model,delta,info.J("last_token_usage").ValueKind==JsonValueKind.Object&&TokenUsage.Read(info.J("last_token_usage"))==delta));continue;
                }
                if(type=="event_msg"&&p.S("type")=="task_complete") {string t=p.S("turn_id",turn);if(log.Turns.TryGetValue(t,out var i))i.Finished=true;Artifacts(p.S("last_agent_message"),t);continue;}
                if(type=="response_item"&&(p.S("type")=="function_call"||p.S("type")=="custom_tool_call")){Ensure(turn,stamp);Artifacts(p.S("arguments",p.S("input")),turn);}
                if(type=="response_item"&&p.S("type")=="message"&&p.S("role")=="assistant")Artifacts(string.Join("\n",p.J("content").Items().Select(x=>x.S("text"))),turn);
            }
        }
        log.Samples=modern?structured:legacy;
        if(log.SessionID.Length==0){log.SessionID="log:"+Path.GetFileNameWithoutExtension(path);foreach(var i in log.Turns.Values)i.SessionID=log.SessionID;log.Samples=log.Samples.Select(s=>s with{SessionID=log.SessionID}).ToList();}
        var referenced=log.Samples.Select(s=>s.TurnID).ToHashSet();log.Turns=log.Turns.Where(x=>referenced.Contains(x.Key)).ToDictionary();return log;
    }
}
