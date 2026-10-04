using System;
using System.IO;
using System.IO.Pipes;
using System.Threading;
using System.Threading.Tasks;

namespace CodexLedger.Windows;

public static class AppInstance {
    public static string PipeName=>"CodexLedger-"+Environment.UserName;
    public static bool Send(string command,string? pipeName=null){
        try{using var pipe=new NamedPipeClientStream(".",pipeName??PipeName,PipeDirection.Out,PipeOptions.CurrentUserOnly);pipe.Connect(2000);using var writer=new StreamWriter(pipe);writer.WriteLine(command);writer.Flush();return true;}
        catch(Exception e)when(e is IOException or TimeoutException or UnauthorizedAccessException){return false;}
    }
    public static async Task Listen(Action<string> received,CancellationToken token,string? pipeName=null){
        while(!token.IsCancellationRequested){
            try{using var pipe=new NamedPipeServerStream(pipeName??PipeName,PipeDirection.In,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous|PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(token).ConfigureAwait(false);using var timeout=CancellationTokenSource.CreateLinkedTokenSource(token);timeout.CancelAfter(TimeSpan.FromSeconds(5));
                using var reader=new StreamReader(pipe);var buffer=new char[64];int count=0;
                while(count<buffer.Length){int n=await reader.ReadAsync(buffer.AsMemory(count,1),timeout.Token).ConfigureAwait(false);if(n==0||buffer[count]=='\n')break;count+=n;}
                var command=count<buffer.Length?new string(buffer,0,count).Trim():string.Empty;
                if(command is "dashboard" or "overview")received(command);
            }catch(OperationCanceledException){if(token.IsCancellationRequested)return;}catch(IOException){await Task.Delay(100,token).ConfigureAwait(false);}
        }
    }
}
