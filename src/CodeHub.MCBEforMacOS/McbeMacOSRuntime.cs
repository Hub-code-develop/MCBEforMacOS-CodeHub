namespace CodeHub.MCBEforMacOS;

/// <summary>
/// macOS 上运行基岩版(GDK 版)所需的运行时目录布局。
/// </summary>
/// <remarks>
/// <para>
/// 运行时树由三部分组成:
/// <list type="bullet">
///   <item><c>wine/</c> —— Wine(WineGDK 分支)安装树,含 <c>xgameruntime.dll</c>(PE)与 <c>xgameruntime.so</c>(unix)。</item>
///   <item><c>xodus/xodus-service</c> —— 原生 macOS 进程,负责 MSA/XSTS/许可,监听 <c>/tmp/xodus.sock</c>。</item>
///   <item><c>render/</c> —— MoltenVK、DXVK、vkd3d-proton。</item>
/// </list>
/// </para>
/// <para>
/// Wine 通过自身可执行文件位置解析 <c>lib/wine</c>,因此 <c>bin/</c> 与 <c>lib/</c> 必须保持同级,整棵树可以搬移。
/// </para>
/// </remarks>
public sealed class McbeMacOSRuntime
{
    /// <summary>随应用一起发布的运行时目录名。</summary>
    public const string BundledDirectoryName = "mcbe-macos";

    /// <summary>用于显式指定运行时根目录的环境变量。</summary>
    public const string RootEnvironmentVariable = "MCBE_MACOS_RUNTIME_DIR";

    private McbeMacOSRuntime(string root) => Root = Path.GetFullPath(root);

    /// <summary>运行时根目录。</summary>
    public string Root { get; }

    public string WineRoot => Path.Combine(Root, "wine");

    /// <summary>wine 加载器,用于启动 Windows PE 程序。</summary>
    public string WineBinary => Path.Combine(WineRoot, "bin", "wine");

    public string WineServerBinary => Path.Combine(WineRoot, "bin", "wineserver");

    /// <summary>PE 侧模块目录,含 <c>xgameruntime.dll</c>。</summary>
    public string WineWindowsLibraryDirectory => Path.Combine(WineRoot, "lib", "wine", "x86_64-windows");

    /// <summary>unix 侧模块目录,含 <c>xgameruntime.so</c>。</summary>
    public string WineUnixLibraryDirectory => Path.Combine(WineRoot, "lib", "wine", "x86_64-unix");

    public string XodusServiceBinary => Path.Combine(Root, "xodus", "xodus-service");

    public string RenderRoot => Path.Combine(Root, "render");

    public string MoltenVkLibrary => Path.Combine(RenderRoot, "lib", "libMoltenVK.dylib");

    public string VulkanIcdManifest => Path.Combine(RenderRoot, "vulkan", "icd.d", "MoltenVK_icd.json");

    public string DxvkDirectory => Path.Combine(RenderRoot, "dxvk");

    public string Vkd3dProtonDirectory => Path.Combine(RenderRoot, "vkd3d-proton");

    /// <summary>必需文件是否齐全。</summary>
    public bool IsComplete =>
        File.Exists(WineBinary) &&
        File.Exists(Path.Combine(WineWindowsLibraryDirectory, "xgameruntime.dll")) &&
        File.Exists(Path.Combine(WineUnixLibraryDirectory, "xgameruntime.so")) &&
        File.Exists(XodusServiceBinary) &&
        File.Exists(MoltenVkLibrary);

    public static McbeMacOSRuntime ForRoot(string root) => new(root);

    /// <summary>
    /// 依次尝试:环境变量 → 应用目录下的 <c>mcbe-macos</c> → 向上级目录查找 → 用户支持目录。
    /// 找不到时返回 <c>null</c>。
    /// </summary>
    public static McbeMacOSRuntime? Locate()
    {
        foreach (var candidate in EnumerateCandidates())
        {
            if (candidate is not null && Directory.Exists(Path.Combine(candidate, "wine")))
                return ForRoot(candidate);
        }
        return null;
    }

    private static IEnumerable<string?> EnumerateCandidates()
    {
        var configured = Environment.GetEnvironmentVariable(RootEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(configured))
            yield return configured;

        var baseDirectory = AppContext.BaseDirectory;
        yield return Path.Combine(baseDirectory, BundledDirectoryName);

        var directory = new DirectoryInfo(baseDirectory);
        for (var depth = 0; depth < 4 && directory is not null; depth++, directory = directory.Parent)
            yield return Path.Combine(directory.FullName, BundledDirectoryName);

        yield return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "Library", "Application Support", "MChub", "Bedrock", "runtime", "current");
    }
}