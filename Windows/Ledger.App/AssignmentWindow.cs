using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using CodexLedger;
namespace CodexLedger.Windows;
public sealed class AssignmentWindow : Window {
    public AssignmentWindow(Window owner,LedgerState state,string goalID,string? initial) {
        Owner=owner;Title=state.T("添加工作")+" · "+(state.Book.Goals.FirstOrDefault(g=>g.ID==goalID)?.Name??state.T("未归入目标"));Width=620;Height=580;WindowStartupLocation=WindowStartupLocation.CenterOwner;Background=owner.Background;Foreground=owner.Foreground;
        var body=new StackPanel{Margin=new Thickness(20)};Content=body;
        var search=new TextBox{Margin=new Thickness(0,4,0,8)};body.Children.Add(new TextBlock{Text=state.T("搜索项目、路径或对话")});body.Children.Add(search);
        var choices=state.Lifetime.Turns.GroupBy(t=>t.Project.ID).Select(g=>(key:"project:"+g.Key,label:state.T("项目")+" · "+g.First().Project.Name+" · "+g.First().Project.Path))
            .Concat(state.Lifetime.Turns.GroupBy(t=>t.SessionID).Select(g=>(key:"conversation:"+g.Key,label:state.T("对话")+" · "+state.ChatTitle(g.Key))))
            .Concat(state.Lifetime.Turns.Select(t=>(key:"turn:"+t.ID,label:state.T("任务轮次")+" · "+t.Title))).ToArray();
        var target=new ListBox{Height=100,DisplayMemberPath="label"};body.Children.Add(target);
        void Refill(){target.ItemsSource=choices.Where(c=>search.Text.Length==0||c.label.Contains(search.Text,StringComparison.OrdinalIgnoreCase)).Select(c=>new Choice(c.key,c.label)).ToArray();if(initial!=null)target.SelectedItem=target.Items.Cast<Choice>().FirstOrDefault(c=>c.key==initial);}
        search.TextChanged+=(_,_)=>Refill();Refill();
        var mode=new ComboBox{Margin=new Thickness(0,10,0,8),ItemsSource=new[]{state.T("仅选中的历史工作"),state.T("从指定日期开始"),state.T("整个项目或对话")},SelectedIndex=0};body.Children.Add(mode);
        var date=new DatePicker{SelectedDate=DateTime.Today,IsEnabled=false};body.Children.Add(date);var ongoing=new CheckBox{Content=state.T("持续包含后续开始的轮次"),IsEnabled=false,Margin=new Thickness(0,8,0,8)};body.Children.Add(ongoing);
        var turns=new StackPanel();body.Children.Add(new ScrollViewer{Content=turns,Height=100});var preview=new TextBlock{TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,12,0,12)};body.Children.Add(preview);
        AttributionRule? Rule(){if(target.SelectedItem is not Choice choice)return null;var split=choice.key.IndexOf(':');return new(Guid.NewGuid().ToString(),new(choice.key[..split],choice.key[(split+1)..]),goalID,mode.SelectedIndex==0?"selected":mode.SelectedIndex==1?"fromDate":"entire",turns.Children.OfType<CheckBox>().Where(c=>c.IsChecked==true).Select(c=>(string)c.Tag).ToHashSet(),mode.SelectedIndex==1?new DateTimeOffset(date.SelectedDate??DateTime.Today).ToUniversalTime():null,mode.SelectedIndex!=0&&ongoing.IsChecked!=true?DateTimeOffset.UtcNow:null,DateTimeOffset.UtcNow);}
        void Preview(){var rule=Rule();if(rule==null){preview.Text=state.T("请选择工作");return;}var result=state.Book.Preview(rule,state.Lifetime.Turns);preview.Text=state.T("归属预览")+" · "+result.Turns.Count+" "+state.T("任务轮次")+" · "+state.T(result.Cost.Money)+" USD\n"+string.Join("\n",result.Displaced.Select(d=>state.T("将从以下目标移出工作")+": "+state.Book.Goals.First(g=>g.ID==d.Key).Name+" · "+d.Value));}
        target.SelectionChanged+=(_,_)=>{turns.Children.Clear();if(target.SelectedItem is Choice choice){foreach(var t in state.Lifetime.Turns.Where(t=>choice.key=="project:"+t.Project.ID||choice.key=="conversation:"+t.SessionID||choice.key=="turn:"+t.ID)){var check=new CheckBox{Content=t.Title+" · "+state.T(t.Cost.Money)+" USD",Tag=t.ID,IsChecked=true};check.Checked+=(_,_)=>Preview();check.Unchecked+=(_,_)=>Preview();turns.Children.Add(check);}}Preview();};
        mode.SelectionChanged+=(_,_)=>{date.IsEnabled=mode.SelectedIndex==1;ongoing.IsEnabled=mode.SelectedIndex!=0&&state.Book.Goals.FirstOrDefault(g=>g.ID==goalID)?.CompletedAt==null;Preview();};date.SelectedDateChanged+=(_,_)=>Preview();ongoing.Checked+=(_,_)=>Preview();ongoing.Unchecked+=(_,_)=>Preview();
        var buttons=new StackPanel{Orientation=Orientation.Horizontal};var cancel=new Button{Content=state.T("取消"),IsCancel=true,Padding=new Thickness(12,6,12,6)};buttons.Children.Add(cancel);var save=new Button{Content=state.T("保存归属"),IsDefault=true,Padding=new Thickness(12,6,12,6),Margin=new Thickness(8,0,0,0)};save.Click+=(_,_)=>{if(Rule() is {} rule){state.Apply(rule);DialogResult=true;}};buttons.Children.Add(save);body.Children.Add(buttons);
        if(initial!=null){target.SelectedItem=null;target.SelectedItem=target.Items.Cast<Choice>().FirstOrDefault(c=>c.key==initial);}Preview();
    }
    public sealed record Choice(string key,string label);
}
