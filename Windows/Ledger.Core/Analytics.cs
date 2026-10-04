using Microsoft.Data.Sqlite;
using System.Text;
namespace CodexLedger;
public sealed class ProjectResolver {
    private readonly Dictionary<string,(DateTime,ProjectIdentity)> cache=new(OperatingSystem.IsWindows()?StringComparer.OrdinalIgnoreCase:StringComparer.Ordinal);
    public static string Normalize(string path) { if(string.IsNullOrWhiteSpace(path)||!Path.IsPathFullyQualified(path))return "";var full=Path.GetFullPath(path);var root=Path.GetPathRoot(full)!;var current=root;
        foreach(var segment in full[root.Length..].Split([Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar],StringSplitOptions.RemoveEmptyEntries)) {
            current=Path.Combine(current,segment);var dir=new DirectoryInfo(current);
            if(dir.Exists&&(dir.Attributes&FileAttributes.ReparsePoint)!=0)current=dir.ResolveLinkTarget(true)?.FullName??current;
        }
        return Path.TrimEndingDirectorySeparator(current); }
    public ProjectIdentity Resolve(string directory) {
        string path;try{path=Normalize(directory);}catch(Exception e)when(e is ArgumentException or NotSupportedException or IOException){return ProjectIdentity.Unknown;}
        if(path.Length==0)return ProjectIdentity.Unknown;
        if(cache.TryGetValue(path,out var entry)&&DateTime.UtcNow-entry.Item1<TimeSpan.FromMinutes(5))return entry.Item2;
        string ID(string s)=>OperatingSystem.IsWindows()?s.ToUpperInvariant():s;
        var result=new ProjectIdentity("directory:"+ID(path),Path.GetFileName(path),path);
        var current=new DirectoryInfo(path);
        while(current!=null) {
            var marker=Path.Combine(current.FullName,".git");
            if(Directory.Exists(marker)||File.Exists(marker)) {
                try {
                    string git;if(Directory.Exists(marker))git=marker;else {var text=Pointer(marker);if(text==null||!text.StartsWith("gitdir: ",StringComparison.Ordinal))break;git=Path.GetFullPath(text[8..],current.FullName);}
                    var commonMarker=Path.Combine(git,"commondir");var common=git;
                    if(File.Exists(commonMarker)){var pointer=Pointer(commonMarker);if(string.IsNullOrEmpty(pointer))break;common=Path.GetFullPath(pointer,git);}
                    if(File.Exists(Path.Combine(git,"HEAD"))&&Directory.Exists(Path.Combine(common,"objects"))&&Directory.Exists(Path.Combine(common,"refs"))) {
                        var root=Path.GetFileName(common)==".git"?Directory.GetParent(common)?.FullName??current.FullName:current.FullName;
                        result=new("git:"+ID(Normalize(common)),Path.GetFileName(root),root);
                    }
                }catch(Exception e)when(e is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException or DecoderFallbackException){}break;
            }
            current=current.Parent;
        }
        cache[path]=(DateTime.UtcNow,result);return result;
    }
    private static string? Pointer(string file) {
        var fi=new FileInfo(file);if(!fi.Exists||fi.Length>16384||(fi.Attributes&FileAttributes.Directory)!=0)return null;
        using var stream=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete);var data=new byte[16385];int count=stream.ReadAtLeast(data,1,false);if(count>16384)return null;
        var text=new UTF8Encoding(false,true).GetString(data,0,count).TrimEnd('\r','\n');return text.IndexOfAny(['\r','\n','\0'])>=0?null:text;
    }
}
public static class ConversationMetadata {
    public static Dictionary<string,string> Titles(string root) {
        foreach(var folder in new[]{root,Path.Combine(root,"sqlite")}) {
            if(!Directory.Exists(folder))continue;
            try {foreach(var file in Directory.EnumerateFiles(folder,"state_*.sqlite").OrderDescending()) {
                try {using var db=new SqliteConnection(new SqliteConnectionStringBuilder{DataSource=file,Mode=SqliteOpenMode.ReadOnly,Pooling=false}.ToString());db.Open();
                    using var schema=db.CreateCommand();schema.CommandText="PRAGMA table_info(threads)";schema.CommandTimeout=1;var columns=new HashSet<string>();using(var r=schema.ExecuteReader())while(r.Read())columns.Add(r.GetString(1));if(!columns.Contains("id")||!columns.Contains("title"))continue;
                    using var cmd=db.CreateCommand();cmd.CommandText="SELECT id,title FROM threads";cmd.CommandTimeout=1;using var reader=cmd.ExecuteReader();var titles=new Dictionary<string,string>();while(reader.Read())if(!reader.IsDBNull(0)&&!reader.IsDBNull(1)){var t=reader.GetString(1).Trim();if(t.Length>0)titles[reader.GetString(0)]=t[..Math.Min(500,t.Length)];}if(titles.Count>0)return titles;
                }catch(Exception e)when(e is SqliteException or IOException or UnauthorizedAccessException){}
            }}catch(Exception e)when(e is IOException or UnauthorizedAccessException){}
        }return [];
    }
}
public sealed class LedgerScanner {
    private readonly LogParser parser=new();private readonly ProjectResolver resolver=new();
    private readonly Dictionary<string,(long,DateTime,ParsedLog)> cache=[];
    public TimeZoneInfo Zone {get;}
    public LedgerScanner(TimeZoneInfo? zone=null)=>Zone=zone??TimeZoneInfo.Local;
    public (List<ParsedLog> Logs,List<string> Warnings) Scan(string root) {
        var logs=new List<ParsedLog>();var warnings=new List<string>();bool found=false;var paths=new HashSet<string>();
        void Walk(string folder) {
            try {
                foreach(var file in Directory.EnumerateFiles(folder,"*.jsonl")) {
                    paths.Add(file);try {var f=new FileInfo(file);if(cache.TryGetValue(file,out var c)&&c.Item1==f.Length&&c.Item2==f.LastWriteTimeUtc)logs.Add(c.Item3);else {var log=parser.Parse(file);cache[file]=(f.Length,f.LastWriteTimeUtc,log);logs.Add(log);}}
                    catch(Exception e)when(e is IOException or UnauthorizedAccessException or System.Text.Json.JsonException){warnings.Add(Path.GetFileName(file)+": "+e.Message);}
                }
                foreach(var d in Directory.EnumerateDirectories(folder))if((File.GetAttributes(d)&FileAttributes.ReparsePoint)==0)Walk(d);
            }catch(Exception e)when(e is IOException or UnauthorizedAccessException){warnings.Add(Path.GetFileName(folder)+": "+e.Message);}
        }
        foreach(var name in new[]{"sessions","archived_sessions"}){var folder=Path.Combine(root,name);if(!Directory.Exists(folder))continue;found=true;Walk(folder);}
        foreach(var key in cache.Keys.Where(x=>!paths.Contains(x)).ToArray())cache.Remove(key);
        if(!found)warnings.Add("没有找到 sessions 或 archived_sessions。请在设置中选择 Codex 数据目录。");return(logs,warnings);
    }
    public Snapshot Snapshot(IReadOnlyList<ParsedLog> logs,DateScope scope,DateTimeOffset now,IReadOnlyList<string>? warnings=null,IReadOnlyDictionary<string,string>? overrides=null) {
        var range=Dates.Interval(scope,now,Zone);var infos=new Dictionary<string,TurnInfo>();var internals=logs.Where(l=>l.InternalAgent).Select(l=>l.SessionID).ToHashSet();
        foreach(var log in logs)foreach(var i in log.Turns.Values)infos[log.SessionID+":"+i.ID]=i;
        var roots=new Dictionary<string,string>();foreach(var i in infos.Values.Where(i=>!internals.Contains(i.SessionID)))roots.TryAdd(i.ID,i.SessionID+":"+i.ID);
        var seen=new HashSet<string>();var groups=new Dictionary<string,List<UsageSample>>();var childIDs=new HashSet<string>();
        foreach(var log in logs.OrderBy(l=>l.Path,StringComparer.Ordinal))foreach(var s in log.Samples.Where(s=>s.Date>=range.Start&&s.Date<range.End)) {
            if(!seen.Add(s.ID))continue;string key=s.SessionID+":"+s.TurnID;
            if(internals.Contains(s.SessionID)&&roots.TryGetValue(s.RootTurnID,out var owner)){key=owner;childIDs.Add(s.ID);}
            if(!groups.TryGetValue(key,out var group)){group=[];groups[key]=group;}group.Add(s);
        }
        var turns=new List<LedgerTurn>();foreach(var (id,samples) in groups) {
            var first=samples.MinBy(s=>s.Date)!;infos.TryGetValue(id,out var info);var artifacts=(info?.Artifacts??[]).Where(x=>Classifier.AssociatedFile(x)&&File.Exists(x)).ToArray();
            var category=Classifier.Category(info?.Prompt??"",artifacts,info?.InheritedCategory??"unknown",internals.Contains(info?.SessionID??first.SessionID));if(overrides!=null&&overrides.TryGetValue(id,out var manual))category=manual;
            var title=info?.Prompt.Trim()??"";if(title.Length==0)title=category=="background"?"Codex 后台检查":"未记录用户请求";
            var cwd=info?.WorkingDirectory??"";
            turns.Add(new(id,info?.SessionID??first.SessionID,title[..Math.Min(200,title.Length)],category,samples.Aggregate(new TokenUsage(),(a,s)=>a+s.Usage),first.Date,samples.Max(s=>s.Date),info?.Finished??false,samples.Count,samples.Count(s=>childIDs.Contains(s.ID)),cwd,resolver.Resolve(cwd),samples.ToArray(),artifacts));
        }
        return new(turns.OrderByDescending(t=>t.Usage.Total).ThenBy(t=>t.ID,StringComparer.Ordinal).ToArray(),warnings??[],logs.Count,logs.Sum(l=>l.Malformed));
    }
    public IReadOnlyList<DailyUsage> Daily(IReadOnlyList<LedgerTurn> month,DateTimeOffset now) {
        var start=DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(now,Zone).Date).AddDays(-29);
        var samples=month.SelectMany(t=>t.Samples).GroupBy(s=>DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(s.Date,Zone).Date)).ToDictionary(g=>g.Key,g=>g.ToArray());
        return Enumerable.Range(0,30).Select(n=>{var date=start.AddDays(n);var list=samples.GetValueOrDefault(date)??[];return new DailyUsage(date,list.Aggregate(new TokenUsage(),(a,s)=>a+s.Usage),list.Length,list.Aggregate(new CostEstimate(),(a,s)=>a+s.Cost));}).ToArray();
    }
}
