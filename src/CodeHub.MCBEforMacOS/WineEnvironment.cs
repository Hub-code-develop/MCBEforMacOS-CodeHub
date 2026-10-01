namespace CodeHub.MCBEforMacOS;

/// <summary>
/// 由运行时树推导出启动 Windows GDK 版基岩版所需的 Wine 环境变量。
/// </summary>
public static class WineEnvironment
{
    /// <summary>
    /// 用原生 DXVK / vkd3d-proton 覆盖 Wine 自带的 d3d11/dxgi/d3d12 实现;
    /// xgameruntime 也走原生,以便加载 WineGDK 的 XUser 实现。
    /// </summary>
    private const string DllOverrides =
        "d3d11,d3d10core,dxgi=n;d3d12,d3d12core=n;xgameruntime=n,b";

    public static Dictionary<string, string> Create(McbeMacOSRuntime runtime, string prefixPath)
    {
        ArgumentNullException.ThrowIfNull(runtime);
        ArgumentException.ThrowIfNullOrWhiteSpace(prefixPath);

        var environment = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["WINEPREFIX"] = Path.GetFullPath(prefixPath),
            ["WINELOADER"] = runtime.WineBinary,
            ["WINESERVER"] = runtime.WineServerBinary,
            ["WINEDLLPATH"] = runtime.WineWindowsLibraryDirectory,
            ["WINEDLLOVERRIDES"] = DllOverrides,
            // MoltenVK 只在 unix 侧使用;指向 ICD 清单即可让 winevulkan 找到它。
            ["VK_ICD_FILENAMES"] = runtime.VulkanIcdManifest,
            ["VK_DRIVER_FILES"] = runtime.VulkanIcdManifest,
            // 关闭 Wine 的调试输出,避免与游戏的 stderr 混在一起。
            ["WINEDEBUG"] = "-all",
        };

        if (File.Exists(runtime.MoltenVkLibrary))
        {
            var existing = Environment.GetEnvironmentVariable("DYLD_FALLBACK_LIBRARY_PATH");
            var libraryDirectory = Path.GetDirectoryName(runtime.MoltenVkLibrary)!;
            environment["DYLD_FALLBACK_LIBRARY_PATH"] =
                string.IsNullOrEmpty(existing) ? libraryDirectory : $"{libraryDirectory}:{existing}";
        }

        return environment;
    }

    /// <summary>按 <paramref name="environment"/> 构造 <see cref="System.Diagnostics.ProcessStartInfo"/>。</summary>
    public static System.Diagnostics.ProcessStartInfo CreateStartInfo(
        McbeMacOSRuntime runtime, string prefixPath, string executable, string? arguments,
        string workingDirectory)
    {
        var startInfo = new System.Diagnostics.ProcessStartInfo
        {
            FileName = runtime.WineBinary,
            Arguments = string.IsNullOrWhiteSpace(arguments) ? $"\"{executable}\"" : $"\"{executable}\" {arguments}",
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
        };

        foreach (var (key, value) in Create(runtime, prefixPath))
            startInfo.Environment[key] = value;

        return startInfo;
    }
}