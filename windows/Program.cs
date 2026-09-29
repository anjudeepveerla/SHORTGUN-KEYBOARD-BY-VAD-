using System.ComponentModel;
using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;
using System.Windows.Forms;

namespace ShotgunKeyboard;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            BundledSounds.Extract();
            if (args.Contains("--self-test"))
            {
                foreach (var id in BundledSounds.Ids)
                {
                    using var audio = new AudioFileReader(BundledSounds.PathFor(id));
                    if (audio.TotalTime <= TimeSpan.Zero) return 1;
                }
                return 0;
            }
        }
        catch (Exception ex)
        {
            if (!args.Contains("--self-test"))
                MessageBox.Show($"Bundled sounds could not load: {ex.Message}", "ShotgunKeyboard",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
        return 0;
    }
}

internal static class BundledSounds
{
    public static readonly (string Id, string Title, string Filename)[] Entries =
    [
        ("gunshotjbudden", "Gunshot J Budden", "gunshotjbudden.mp3"),
        ("shotgun", "Shotgun", "shotgun.wav"),
        ("boing", "Cartoon Boing", "boing.wav"),
        ("beep", "Censor Beep", "beep.wav"),
        ("fart", "Dry Fart", "fart.wav"),
        ("pew", "Pew Pew", "pew.wav"),
        ("quack", "Quack", "quack.wav"),
        ("applepay", "Apple Pay", "applepay.mp3"),
        ("movie_1", "Movie 1", "movie_1.mp3"),
        ("rizz-sound-effect", "Rizz Sound Effect", "rizz-sound-effect.mp3"),
        ("wrong-answer-sound-effect", "Wrong Answer", "wrong-answer-sound-effect.mp3"),
        ("yes-lara-voice", "Yes Lara Voice", "yes-lara-voice.mp3"),
        ("shocked-sound-effect", "Shocked", "shocked-sound-effect.mp3"),
        ("punch_u4LmMsr", "Punch", "punch_u4LmMsr.mp3"),
        ("maro-jump-sound-effect_1", "Maro Jump", "maro-jump-sound-effect_1.mp3"),
        ("ding-sound-effect_2", "Ding", "ding-sound-effect_2.mp3"),
        ("anime-ahh", "Anime Ahh", "anime-ahh.mp3"),
        ("67_SQlv2Xv", "67", "67_SQlv2Xv.mp3")
    ];
    public static IEnumerable<string> Ids => Entries.Select(entry => entry.Id);
    private static readonly string DirectoryPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ShotgunKeyboard", "Bundled");

    public static string PathFor(string id)
    {
        var entry = Entries.FirstOrDefault(entry => entry.Id == id);
        if (entry == default) throw new ArgumentException($"Unknown bundled sound: {id}");
        return Path.Combine(DirectoryPath, entry.Filename);
    }

    public static void Extract()
    {
        Directory.CreateDirectory(DirectoryPath);
        var assembly = Assembly.GetExecutingAssembly();
        foreach (var entry in Entries)
        {
            using var resource = assembly.GetManifestResourceStream($"ShotgunKeyboard.Sounds.{entry.Filename}")
                ?? throw new FileNotFoundException($"Missing bundled sound: {entry.Filename}");
            var path = PathFor(entry.Id);
            if (File.Exists(path) && new FileInfo(path).Length == resource.Length) continue;
            using var file = File.Create(path);
            resource.CopyTo(file);
        }
    }
}

internal sealed class SoundSettings
{
    public bool Armed { get; set; } = true;
    public bool MultipleSounds { get; set; }
    public float Volume { get; set; } = 0.55f;
    public List<string> SelectedSoundIds { get; set; } = ["gunshotjbudden"];
    public List<CustomSound> CustomSounds { get; set; } = [];
}

internal sealed class CustomSound
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Filename { get; set; } = "";
}

internal sealed class SoundEntry(string id, string title, string path, bool isCustom = false)
{
    public string Id { get; } = id;
    public string Title { get; } = title;
    public string Path { get; } = path;
    public bool IsCustom { get; } = isCustom;
    public override string ToString() => Title;
}

internal sealed class MainForm : Form
{
    private static readonly string DataDirectory =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ShotgunKeyboard");
    private static readonly string CustomDirectory = Path.Combine(DataDirectory, "Sounds");
    private static readonly string SettingsPath = Path.Combine(DataDirectory, "settings.json");
    private readonly SoundSettings settings;
    private readonly List<SoundEntry> sounds = [];
    private readonly CheckedListBox soundList = new();
    private readonly CheckBox armedCheck = new();
    private readonly CheckBox multipleCheck = new();
    private readonly Button selectAllButton = new();
    private readonly ComboBox volumeSelect = new();
    private readonly Label statusLabel = new();
    private readonly NotifyIcon trayIcon = new();
    private readonly System.Windows.Forms.Timer statusTimer = new();
    private KeyboardHook? hook;
    private SoundEngine? audio;
    private bool updatingList;
    private bool quitting;
    private long detectedKeys;

    public MainForm()
    {
        settings = LoadSettings();
        Text = "ShotgunKeyboard";
        ClientSize = new Size(590, 650);
        MinimumSize = MaximumSize = Size;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10);
        Icon = SystemIcons.Application;

        Controls.Add(new Label
        {
            Text = "ShotgunKeyboard",
            Font = new Font("Segoe UI", 22, FontStyle.Bold),
            Location = new Point(24, 18),
            Size = new Size(540, 43)
        });
        Controls.Add(new Label
        {
            Text = "A sound effect for every key press",
            ForeColor = SystemColors.GrayText,
            Location = new Point(26, 65),
            Size = new Size(530, 24)
        });

        var statusPanel = new Panel
        {
            BackColor = SystemColors.ControlLight,
            Location = new Point(24, 104),
            Size = new Size(542, 68)
        };
        statusPanel.Controls.Add(new Label
        {
            Text = "Keyboard monitoring",
            Font = new Font("Segoe UI", 10, FontStyle.Bold),
            Location = new Point(14, 8),
            Size = new Size(330, 23)
        });
        statusLabel.Location = new Point(14, 34);
        statusLabel.Size = new Size(510, 26);
        statusLabel.Text = "Starting…";
        statusPanel.Controls.Add(statusLabel);
        Controls.Add(statusPanel);

        armedCheck.Text = "Armed";
        armedCheck.Location = new Point(24, 188);
        armedCheck.Size = new Size(145, 28);
        armedCheck.Checked = settings.Armed;
        armedCheck.CheckedChanged += (_, _) =>
        {
            settings.Armed = armedCheck.Checked;
            SaveSettings();
        };
        Controls.Add(armedCheck);

        multipleCheck.Text = "Multiple sounds";
        multipleCheck.Location = new Point(190, 188);
        multipleCheck.Size = new Size(190, 28);
        multipleCheck.Checked = settings.MultipleSounds;
        multipleCheck.CheckedChanged += (_, _) =>
        {
            settings.MultipleSounds = multipleCheck.Checked;
            if (!settings.MultipleSounds && settings.SelectedSoundIds.Count > 1)
                settings.SelectedSoundIds = [settings.SelectedSoundIds[^1]];
            selectAllButton.Enabled = settings.MultipleSounds;
            SaveSettings();
            RefreshSoundList();
        };
        Controls.Add(multipleCheck);

        Controls.Add(new Label
        {
            Text = "Sounds",
            Font = new Font("Segoe UI", 13, FontStyle.Bold),
            Location = new Point(24, 230),
            Size = new Size(100, 27)
        });
        Controls.Add(new Label
        {
            Text = "Select one sound, or enable Multiple sounds to mix randomly.",
            ForeColor = SystemColors.GrayText,
            Location = new Point(125, 236),
            Size = new Size(440, 20)
        });

        soundList.Location = new Point(24, 263);
        soundList.Size = new Size(542, 248);
        soundList.IntegralHeight = false;
        soundList.CheckOnClick = true;
        soundList.ItemCheck += SoundListOnItemCheck;
        Controls.Add(soundList);

        var addButton = new Button
        {
            Text = "Add Sounds…",
            Location = new Point(24, 523),
            Size = new Size(128, 32)
        };
        addButton.Click += (_, _) => AddSounds();
        Controls.Add(addButton);

        var removeButton = new Button
        {
            Text = "Remove Added",
            Location = new Point(160, 523),
            Size = new Size(135, 32)
        };
        removeButton.Click += (_, _) => RemoveSelectedCustomSound();
        Controls.Add(removeButton);

        selectAllButton.Text = "Select All";
        selectAllButton.Location = new Point(448, 523);
        selectAllButton.Size = new Size(118, 32);
        selectAllButton.Enabled = settings.MultipleSounds;
        selectAllButton.Click += (_, _) =>
        {
            settings.SelectedSoundIds = sounds.Select(sound => sound.Id).ToList();
            SaveSettings();
            RefreshSoundList();
        };
        Controls.Add(selectAllButton);

        Controls.Add(new Label
        {
            Text = "Volume",
            Location = new Point(24, 573),
            Size = new Size(75, 25)
        });
        volumeSelect.Location = new Point(100, 568);
        volumeSelect.Size = new Size(135, 30);
        volumeSelect.DropDownStyle = ComboBoxStyle.DropDownList;
        volumeSelect.Items.AddRange(["Loud", "Medium", "Quiet"]);
        volumeSelect.SelectedIndex = settings.Volume > 0.75f ? 0 : settings.Volume > 0.35f ? 1 : 2;
        volumeSelect.SelectedIndexChanged += (_, _) =>
        {
            settings.Volume = volumeSelect.SelectedIndex switch
            {
                0 => 1.0f,
                2 => 0.2f,
                _ => 0.55f
            };
            SaveSettings();
        };
        Controls.Add(volumeSelect);

        var testButton = new Button
        {
            Text = "Test Selected Sound",
            Location = new Point(374, 566),
            Size = new Size(192, 34)
        };
        testButton.Click += (_, _) => PlaySelectedSound();
        Controls.Add(testButton);

        Controls.Add(new Label
        {
            Text = "Close the window to keep sounds active. Reopen from the tray icon.",
            ForeColor = SystemColors.GrayText,
            Location = new Point(24, 618),
            Size = new Size(542, 22)
        });

        var trayMenu = new ContextMenuStrip();
        trayMenu.Items.Add("Open ShotgunKeyboard", null, (_, _) => ShowWindow());
        trayMenu.Items.Add("Quit ShotgunKeyboard", null, (_, _) => Quit());
        trayIcon.Icon = SystemIcons.Application;
        trayIcon.Text = "ShotgunKeyboard";
        trayIcon.ContextMenuStrip = trayMenu;
        trayIcon.DoubleClick += (_, _) => ShowWindow();
        trayIcon.Visible = true;

        statusTimer.Interval = 1000;
        statusTimer.Tick += (_, _) => UpdateStatus();
        statusTimer.Start();
        RefreshSoundList();
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        try
        {
            audio = new SoundEngine();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"Audio output could not start: {ex.Message}", "ShotgunKeyboard",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        try
        {
            hook = new KeyboardHook(() =>
            {
                Interlocked.Increment(ref detectedKeys);
                if (!settings.Armed || audio is null || settings.SelectedSoundIds.Count == 0) return;
                var id = settings.SelectedSoundIds[Random.Shared.Next(settings.SelectedSoundIds.Count)];
                var sound = sounds.FirstOrDefault(entry => entry.Id == id);
                if (sound is null) return;
                var path = sound.Path;
                var volume = settings.Volume;
                ThreadPool.QueueUserWorkItem(_ =>
                {
                    try { audio.Play(path, volume); }
                    catch { /* A deleted or unsupported file should not interrupt typing. */ }
                });
            });
        }
        catch (Win32Exception ex)
        {
            MessageBox.Show(this, $"Keyboard monitoring could not start: {ex.Message}", "ShotgunKeyboard",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        UpdateStatus();
    }

    private static SoundSettings LoadSettings()
    {
        try
        {
            return JsonSerializer.Deserialize<SoundSettings>(File.ReadAllText(SettingsPath)) ?? new SoundSettings();
        }
        catch
        {
            return new SoundSettings();
        }
    }

    private void SaveSettings()
    {
        Directory.CreateDirectory(DataDirectory);
        var temp = SettingsPath + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temp, SettingsPath, true);
    }

    private void RefreshSoundList()
    {
        sounds.Clear();
        foreach (var (id, title, _) in BundledSounds.Entries)
        {
            var path = BundledSounds.PathFor(id);
            if (File.Exists(path)) sounds.Add(new SoundEntry(id, title, path));
        }

        foreach (var custom in settings.CustomSounds)
        {
            var path = Path.Combine(CustomDirectory, custom.Filename);
            if (File.Exists(path)) sounds.Add(new SoundEntry(custom.Id, custom.Name, path, true));
        }

        var valid = sounds.Select(sound => sound.Id).ToHashSet();
        settings.SelectedSoundIds = settings.SelectedSoundIds.Where(valid.Contains).Distinct().ToList();
        if (!settings.MultipleSounds && settings.SelectedSoundIds.Count > 1)
            settings.SelectedSoundIds = [settings.SelectedSoundIds[^1]];
        if (settings.SelectedSoundIds.Count == 0 && sounds.Count > 0)
            settings.SelectedSoundIds = [sounds[0].Id];

        updatingList = true;
        soundList.Items.Clear();
        foreach (var sound in sounds)
        {
            var index = soundList.Items.Add(sound);
            soundList.SetItemChecked(index, settings.SelectedSoundIds.Contains(sound.Id));
        }
        updatingList = false;
        SaveSettings();
    }

    private void SoundListOnItemCheck(object? sender, ItemCheckEventArgs e)
    {
        if (updatingList) return;
        if (e.NewValue == CheckState.Unchecked &&
            (settings.MultipleSounds ? soundList.CheckedItems.Count <= 1 : true))
        {
            e.NewValue = CheckState.Checked;
            return;
        }

        if (!settings.MultipleSounds && e.NewValue == CheckState.Checked)
        {
            updatingList = true;
            for (var index = 0; index < soundList.Items.Count; index++)
                if (index != e.Index) soundList.SetItemChecked(index, false);
            updatingList = false;
        }

        BeginInvoke(new Action(() =>
        {
            settings.SelectedSoundIds = soundList.CheckedItems
                .Cast<SoundEntry>().Select(sound => sound.Id).ToList();
            SaveSettings();
        }));
    }

    private void AddSounds()
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Add sounds to ShotgunKeyboard",
            Filter = "Audio files|*.wav;*.mp3;*.aiff;*.m4a|All files|*.*",
            Multiselect = true
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;

        Directory.CreateDirectory(CustomDirectory);
        var added = new List<string>();
        var failures = new List<string>();
        foreach (var source in dialog.FileNames)
        {
            var id = Guid.NewGuid().ToString("N");
            var filename = id + Path.GetExtension(source).ToLowerInvariant();
            var destination = Path.Combine(CustomDirectory, filename);
            try
            {
                File.Copy(source, destination);
                using (var probe = new AudioFileReader(destination)) { _ = probe.TotalTime; }
                settings.CustomSounds.Add(new CustomSound
                {
                    Id = id,
                    Name = Path.GetFileNameWithoutExtension(source),
                    Filename = filename
                });
                added.Add(id);
            }
            catch (Exception ex)
            {
                if (File.Exists(destination)) File.Delete(destination);
                failures.Add($"{Path.GetFileName(source)}: {ex.Message}");
            }
        }

        if (added.Count > 0)
        {
            settings.SelectedSoundIds = settings.MultipleSounds ? added : [added[^1]];
            RefreshSoundList();
        }
        if (failures.Count > 0)
            MessageBox.Show(this, string.Join(Environment.NewLine, failures),
                "Some sounds could not be added", MessageBoxButtons.OK, MessageBoxIcon.Warning);
    }

    private void RemoveSelectedCustomSound()
    {
        if (soundList.SelectedItem is not SoundEntry { IsCustom: true } selected)
        {
            MessageBox.Show(this, "Select an added sound in the list first.", "ShotgunKeyboard",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        var custom = settings.CustomSounds.First(sound => sound.Id == selected.Id);
        try
        {
            File.Delete(Path.Combine(CustomDirectory, custom.Filename));
            settings.CustomSounds.Remove(custom);
            settings.SelectedSoundIds.Remove(selected.Id);
            RefreshSoundList();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Sound could not be removed",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private void PlaySelectedSound()
    {
        if (audio is null || settings.SelectedSoundIds.Count == 0) return;
        var id = settings.SelectedSoundIds[Random.Shared.Next(settings.SelectedSoundIds.Count)];
        var sound = sounds.FirstOrDefault(entry => entry.Id == id);
        if (sound is null) return;
        try
        {
            audio.Play(sound.Path, settings.Volume);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Sound could not play",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private void UpdateStatus()
    {
        statusLabel.Text = hook is null
            ? "Keyboard monitoring stopped."
            : $"Listening · {Interlocked.Read(ref detectedKeys)} keys detected";
    }

    private void ShowWindow()
    {
        Show();
        WindowState = FormWindowState.Normal;
        Activate();
    }

    private void Quit()
    {
        quitting = true;
        statusTimer.Stop();
        hook?.Dispose();
        audio?.Dispose();
        trayIcon.Visible = false;
        trayIcon.Dispose();
        SaveSettings();
        Close();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!quitting && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnFormClosing(e);
    }
}

internal sealed class KeyboardHook : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmSysKeyDown = 0x0104;
    private readonly HookProc callback;
    private readonly Action keyDown;
    private IntPtr handle;

    public KeyboardHook(Action keyDown)
    {
        this.keyDown = keyDown;
        callback = OnHook;
        handle = SetWindowsHookEx(WhKeyboardLl, callback, GetModuleHandle(null), 0);
        if (handle == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    private IntPtr OnHook(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0 && (wParam == (IntPtr)WmKeyDown || wParam == (IntPtr)WmSysKeyDown))
        {
            try { keyDown(); }
            catch { /* The hook must always pass the key through. */ }
        }
        return CallNextHookEx(handle, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (handle != IntPtr.Zero)
        {
            UnhookWindowsHookEx(handle);
            handle = IntPtr.Zero;
        }
        GC.KeepAlive(callback);
    }

    private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc callback, IntPtr module, uint threadId);
    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string? moduleName);
}

internal sealed class SoundEngine : IDisposable
{
    private readonly object gate = new();
    private readonly MixingSampleProvider mixer =
        new(WaveFormat.CreateIeeeFloatWaveFormat(44_100, 2)) { ReadFully = true };
    private readonly WaveOut output = new();
    private readonly Queue<Voice> voices = new();

    public SoundEngine()
    {
        output.Init(mixer);
        output.Play();
    }

    public void Play(string path, float volume)
    {
        lock (gate)
        {
            var reader = new AudioFileReader(path) { Volume = volume };
            ISampleProvider source = reader;
            if (source.WaveFormat.SampleRate != 44_100)
                source = new WdlResamplingSampleProvider(source, 44_100);
            if (source.WaveFormat.Channels == 1)
                source = new MonoToStereoSampleProvider(source);
            if (source.WaveFormat.Channels != 2)
            {
                reader.Dispose();
                throw new InvalidOperationException("This sound must have one or two audio channels.");
            }

            var voice = new Voice(source, reader);
            while (voices.Count >= 10)
            {
                var old = voices.Dequeue();
                mixer.RemoveMixerInput(old);
                old.Dispose();
            }
            voices.Enqueue(voice);
            mixer.AddMixerInput(voice);
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            output.Stop();
            output.Dispose();
            foreach (var voice in voices) voice.Dispose();
            voices.Clear();
        }
    }

    private sealed class Voice(ISampleProvider source, AudioFileReader reader) : ISampleProvider, IDisposable
    {
        private int disposed;
        public WaveFormat WaveFormat => source.WaveFormat;

        public int Read(Span<float> buffer)
        {
            if (Volatile.Read(ref disposed) != 0) return 0;
            var read = source.Read(buffer);
            if (read == 0) Dispose();
            return read;
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) == 0) reader.Dispose();
        }
    }
}
