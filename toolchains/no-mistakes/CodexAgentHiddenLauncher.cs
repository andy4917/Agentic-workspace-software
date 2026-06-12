using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        string codex = ResolveCodexExecutable();
        if (string.IsNullOrWhiteSpace(codex) || !File.Exists(codex))
        {
            Console.Error.WriteLine("Codex bundled codex.exe not found. Restart or update Codex Desktop.");
            return 1;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = codex,
            Arguments = string.Join(" ", args.Select(QuoteArgument).ToArray()),
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };

        using (var process = new Process { StartInfo = startInfo })
        {
            if (!process.Start())
            {
                Console.Error.WriteLine("Failed to start Codex bundled codex.exe.");
                return 1;
            }

            Thread inputThread = StartInputPump(process.StandardInput.BaseStream);
            Thread outputThread = StartPump(process.StandardOutput.BaseStream, Console.OpenStandardOutput());
            Thread errorThread = StartPump(process.StandardError.BaseStream, Console.OpenStandardError());

            process.WaitForExit();
            JoinQuietly(inputThread);
            JoinQuietly(outputThread);
            JoinQuietly(errorThread);
            return process.ExitCode;
        }
    }

    private static string ResolveCodexExecutable()
    {
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(localAppData))
        {
            localAppData = Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? string.Empty;
        }

        string binRoot = Path.Combine(localAppData, "OpenAI", "Codex", "bin");
        string direct = Path.Combine(binRoot, "codex.exe");
        if (File.Exists(direct))
        {
            return direct;
        }

        if (!Directory.Exists(binRoot))
        {
            return string.Empty;
        }

        return Directory.GetDirectories(binRoot)
            .Select(path => new DirectoryInfo(path))
            .OrderByDescending(info => info.LastWriteTimeUtc)
            .Select(info => Path.Combine(info.FullName, "codex.exe"))
            .FirstOrDefault(File.Exists) ?? string.Empty;
    }

    private static Thread StartInputPump(Stream childInput)
    {
        if (!ShouldForwardStandardInput())
        {
            CloseQuietly(childInput);
            return null;
        }

        var thread = new Thread(() =>
        {
            try
            {
                if (Console.IsInputRedirected)
                {
                    Console.OpenStandardInput().CopyTo(childInput);
                }
            }
            catch (IOException)
            {
            }
            catch (ObjectDisposedException)
            {
            }
            finally
            {
                try
                {
                    childInput.Close();
                }
                catch (IOException)
                {
                }
            }
        });
        thread.IsBackground = true;
        thread.Start();
        return thread;
    }

    private static bool ShouldForwardStandardInput()
    {
        string value = Environment.GetEnvironmentVariable("CODEX_AGENT_HIDDEN_FORWARD_STDIN");
        return string.Equals(value, "1", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
    }

    private static Thread StartPump(Stream input, Stream output)
    {
        var thread = new Thread(() =>
        {
            try
            {
                input.CopyTo(output);
                output.Flush();
            }
            catch (IOException)
            {
            }
            catch (ObjectDisposedException)
            {
            }
        });
        thread.Start();
        return thread;
    }

    private static void JoinQuietly(Thread thread)
    {
        if (thread == null)
        {
            return;
        }

        try
        {
            thread.Join(TimeSpan.FromSeconds(5));
        }
        catch (ThreadStateException)
        {
        }
    }

    private static void CloseQuietly(Stream stream)
    {
        if (stream == null)
        {
            return;
        }

        try
        {
            stream.Close();
        }
        catch (IOException)
        {
        }
        catch (ObjectDisposedException)
        {
        }
    }

    private static string QuoteArgument(string argument)
    {
        if (argument == null)
        {
            return "\"\"";
        }

        if (argument.Length == 0)
        {
            return "\"\"";
        }

        bool needsQuotes = argument.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) >= 0;
        if (!needsQuotes)
        {
            return argument;
        }

        var builder = new StringBuilder();
        builder.Append('"');
        int backslashes = 0;
        foreach (char character in argument)
        {
            if (character == '\\')
            {
                backslashes++;
                continue;
            }

            if (character == '"')
            {
                builder.Append('\\', backslashes * 2 + 1);
                builder.Append('"');
                backslashes = 0;
                continue;
            }

            if (backslashes > 0)
            {
                builder.Append('\\', backslashes);
                backslashes = 0;
            }

            builder.Append(character);
        }

        if (backslashes > 0)
        {
            builder.Append('\\', backslashes * 2);
        }

        builder.Append('"');
        return builder.ToString();
    }
}
