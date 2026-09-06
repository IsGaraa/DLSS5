using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace DLSS5
{
    internal static class Ui
    {
        public static readonly Color Bg        = Color.FromArgb(13, 16, 22);
        public static readonly Color Sidebar   = Color.FromArgb(15, 19, 27);
        public static readonly Color Card      = Color.FromArgb(23, 28, 40);
        public static readonly Color CardHi    = Color.FromArgb(28, 34, 48);
        public static readonly Color Border    = Color.FromArgb(37, 44, 62);
        public static readonly Color Text      = Color.FromArgb(232, 235, 242);
        public static readonly Color Muted     = Color.FromArgb(143, 151, 170);
        public static readonly Color Accent    = Color.FromArgb(143, 212, 0);
        public static readonly Color AccentDim = Color.FromArgb(34, 50, 20);
        public static readonly Color Blue      = Color.FromArgb(62, 139, 255);
        public static readonly Color BlueDim   = Color.FromArgb(22, 38, 62);
        public static readonly Color Danger    = Color.FromArgb(229, 72, 77);
        public static readonly Color DangerDim = Color.FromArgb(60, 24, 26);
        public static readonly Color Gold      = Color.FromArgb(255, 185, 36);
        public static readonly Color GoldDim   = Color.FromArgb(58, 45, 14);

        public static GraphicsPath RoundRect(Rectangle r, int rad)
        {
            var p = new GraphicsPath();
            int d = Math.Min(rad * 2, Math.Min(r.Width, r.Height));
            if (d < 2) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static Font Face(float size, bool bold) { return new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular); }
    }

    internal class RoundedPanel : Panel
    {
        public int Radius { get; set; }
        public bool BorderVisible { get; set; }
        public Color BorderColor { get; set; }

        public RoundedPanel()
        {
            Radius = 10;
            BorderVisible = true;
            BorderColor = Ui.Border;
            DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var br = new SolidBrush(BackColor))
                e.Graphics.FillPath(br, Ui.RoundRect(new Rectangle(0, 0, Width - 1, Height - 1), Radius));
            if (BorderVisible)
                using (var pn = new Pen(BorderColor))
                    e.Graphics.DrawPath(pn, Ui.RoundRect(new Rectangle(0, 0, Width - 1, Height - 1), Radius));
        }
    }

    internal class FlatButton : Button
    {
        private Color _base, _hover;

        public FlatButton()
        {
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            Cursor = Cursors.Hand;
            Font = Ui.Face(9f, true);
            MouseEnter += (s, e) => BackColor = _hover;
            MouseLeave += delegate { BackColor = Enabled ? _base : Color.FromArgb(42, 47, 58); };
            EnabledChanged += delegate { BackColor = Enabled ? _base : Color.FromArgb(42, 47, 58); };
        }

        public void SetColor(Color c)
        {
            _base = c;
            _hover = ControlPaint.Light(c, 0.09f);
            BackColor = _base;
        }
    }

    internal class Pill : Control
    {
        public Color Fill { get; set; }
        public Color TextColor { get; set; }

        public Pill()
        {
            Fill = Ui.AccentDim;
            TextColor = Ui.Accent;
            DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var br = new SolidBrush(Fill))
                g.FillPath(br, Ui.RoundRect(new Rectangle(1, 1, Width - 3, Height - 3), 8));
            using (var br = new SolidBrush(TextColor))
                g.DrawString(Text, Ui.Face(9f, true), br, new PointF(9, 4));
        }
    }

    internal class GameInfo
    {
        public string Dir, Path, Name, Bitness, Api, Label, Via;
        public bool HasNative, ReshadePresent;
        public string ReshadeText;
        public bool Undetected { get { return Api == null || Api.Length == 0; } }
    }

    internal class GameCard : RoundedPanel
    {
        public GameInfo Info { get; private set; }
        public event Action<GameInfo> OnInstall, OnVerify, OnUninstall, OnOpen, OnSelect;
        private readonly Pill _badge;
        private bool _selected;

        public bool Selected
        {
            get { return _selected; }
            set { _selected = value; BorderColor = value ? Ui.Accent : Ui.Border; BackColor = value ? Ui.CardHi : Ui.Card; Invalidate(); }
        }

        public GameCard(GameInfo info)
        {
            Info = info;
            Height = 68;
            Radius = 10;
            BackColor = Ui.Card;
            BorderColor = Ui.Border;
            Padding = new Padding(0, 0, 8, 0);

            var bar = new Panel { Dock = DockStyle.Left, Width = 5, BackColor = AccentOf(info) };
            Controls.Add(bar);

            var title = new Label
            {
                AutoSize = false,
                Text = info.Name,
                Dock = DockStyle.Top,
                Height = 24,
                Padding = new Padding(16, 5, 0, 0),
                TextAlign = ContentAlignment.MiddleLeft,
                Font = Ui.Face(11f, true),
                ForeColor = Ui.Text
            };
            Controls.Add(title);

            var sub = new Label
            {
                AutoSize = false,
                Dock = DockStyle.Top,
                Height = 20,
                Padding = new Padding(16, 0, 0, 0),
                TextAlign = ContentAlignment.MiddleLeft,
                Font = Ui.Face(9f, false),
                ForeColor = Ui.Muted,
                Text = info.Via + "  ·  " + info.Dir,
                AutoEllipsis = true
            };
            Controls.Add(sub);

            _badge = new Pill
            {
                Text = info.Undetected ? "UNKNOWN" : info.Label.ToUpper(),
                Width = info.Undetected ? 96 : 150,
                Height = 22,
                Location = new Point(16, 44),
                Fill = info.Undetected ? Ui.DangerDim : Ui.AccentDim,
                TextColor = info.Undetected ? Ui.Danger : Ui.Accent
            };
            Controls.Add(_badge);

            _badge.Width = info.Undetected ? 96 : (int)(_badge.Text.Length * 7.4f) + 20;

            var right = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.RightToLeft,
                Padding = new Padding(0, 20, 6, 0),
                WrapContents = false
            };
            right.Controls.Add(MkAct("Install", Ui.Accent, info, OnInstall));
            right.Controls.Add(MkAct("Verify", Ui.Blue, info, OnVerify));
            right.Controls.Add(MkAct("Uninstall", Ui.Danger, info, OnUninstall));
            right.Controls.Add(MkAct("Open", Ui.Muted, info, OnOpen));
            Controls.Add(right);

            Click += (s, e) => SelectCard();
            title.Click += (s, e) => SelectCard();
            sub.Click += (s, e) => SelectCard();
            _badge.Click += (s, e) => SelectCard();
            bar.Click += (s, e) => SelectCard();
        }

        private static Color AccentOf(GameInfo i)
        {
            if (i.Undetected) return Ui.Danger;
            if (i.Label.IndexOf("12", StringComparison.Ordinal) >= 0) return Ui.Accent;
            if (i.Label.IndexOf("Vulkan", StringComparison.Ordinal) >= 0) return Ui.Blue;
            if (i.Label.IndexOf("11", StringComparison.Ordinal) >= 0) return Ui.Gold;
            return Ui.Muted;
        }

        private void SelectCard()
        {
            if (OnSelect != null) OnSelect(Info);
        }

        private FlatButton MkAct(string text, Color c, GameInfo info, Action<GameInfo> ev)
        {
            var b = new FlatButton { Text = text, AutoSize = false, Width = 96, Height = 28, Font = Ui.Face(8.5f, true) };
            b.SetColor(c);
            b.Click += (s, e) => { if (ev != null) ev(info); };
            return b;
        }
    }

    internal class BackupCard : RoundedPanel
    {
        public string Dir { get; private set; }
        public event Action<BackupCard> OnRestore, OnOpen;

        public BackupCard(string dir, int entries)
        {
            Dir = dir;
            Height = 64;
            BackColor = Ui.Card;
            var title = new Label
            {
                AutoSize = false, Dock = DockStyle.Top, Height = 24, Padding = new Padding(16, 5, 0, 0),
                TextAlign = ContentAlignment.MiddleLeft, Font = Ui.Face(11f, true), ForeColor = Ui.Text,
                Text = Path.GetFileName(dir.TrimEnd('\\'))
            };
            var sub = new Label
            {
                AutoSize = false, Dock = DockStyle.Top, Height = 20, Padding = new Padding(16, 0, 0, 0),
                TextAlign = ContentAlignment.MiddleLeft, Font = Ui.Face(9f, false), ForeColor = Ui.Muted,
                Text = dir + "   ·   " + entries + " entries", AutoEllipsis = true
            };
            var pill = new Pill { Text = "BACKUP", Width = 84, Height = 22, Location = new Point(16, 42), Fill = Ui.GoldDim, TextColor = Ui.Gold };
            var right = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(0, 17, 6, 0), WrapContents = false };
            var rest = new FlatButton { Text = "Restore originals", AutoSize = false, Width = 130, Height = 28, Font = Ui.Face(8.5f, true) };
            rest.SetColor(Ui.Danger);
            rest.Click += (s, e) => { if (OnRestore != null) OnRestore(this); };
            var opn = new FlatButton { Text = "Open", AutoSize = false, Width = 70, Height = 28, Font = Ui.Face(8.5f, true) };
            opn.SetColor(Ui.Muted);
            opn.Click += (s, e) => { if (OnOpen != null) OnOpen(this); };
            right.Controls.Add(rest);
            right.Controls.Add(opn);
            Controls.Add(title);
            Controls.Add(sub);
            Controls.Add(pill);
            Controls.Add(right);
        }
    }

    public class WizardForm : Form
    {
        private readonly string _appDir;
        private readonly string _scriptPath;
        private readonly string _settingsPath;
        private readonly string _script = "DLSS5-Swapper.ps1";

        private List<string> _folders = new List<string>();
        private readonly List<GameInfo> _library = new List<GameInfo>();
        private GameInfo _selected;

        // nav
        private readonly Dictionary<string, Button> _nav = new Dictionary<string, Button>();
        private readonly Dictionary<string, Panel> _pages = new Dictionary<string, Panel>();
        private Label _pageTitle, _pageSub;
        private Panel _pageHost;

        // library page
        private FlowLayoutPanel _libFlow;
        private Label _libHint, _libStatus;
        private FlatButton _addFolderBtn, _rescanBtn;

        // options page
        private FlatButton _segChicken, _segRenodx;
        private NumericUpDown _passes, _workRes, _presetBox, _intensityBox;
        private ComboBox _styleBox, _mvBox, _feederBox, _apiBox;
        private CheckBox _cleanFry, _texBoost, _uplift, _dryRun, _force, _launch;
        private Label _optTitle, _optHint, _apiNote;
        private Pill _optBadge;
        private FlatButton _optInstall, _optVerify, _optUninst;

        // backups page
        private FlowLayoutPanel _bkFlow;
        private Label _bkStatus;

        // log page
        private TextBox _log;
        private FlatButton _copyLogBtn, _clearLogBtn;

        private bool _busy;

        public WizardForm()
        {
            _appDir = Path.GetDirectoryName(Application.ExecutablePath);
            _scriptPath = Path.Combine(_appDir, _script);
            _settingsPath = Path.Combine(_appDir, "wizard.json");

            Text = "DLSS 5 Swapper";
            Font = Ui.Face(9f, false);
            BackColor = Ui.Bg;
            ForeColor = Ui.Text;
            StartPosition = FormStartPosition.CenterScreen;
            MinimumSize = new Size(1020, 660);
            Size = new Size(1180, 740);
            Load += (s, e) => Boot();
        }

        private void Boot()
        {
            BuildUi();
            LoadFolders();
            Log("[notice] kit/" + (Directory.Exists(Path.Combine(_appDir, "kit")) ? "present" : "missing - first Install builds it") + "\r\n");
            ShowPage("lib");
            Nav("lib");
            RefreshLibrary(silent: true);
        }

        // ---------------------------------------------------------------- nav & pages
        private void BuildUi()
        {
            BuildContent();
            BuildSidebar();
        }

        private void BuildSidebar()
        {
            var sidebar = new Panel { Dock = DockStyle.Left, Width = 220, BackColor = Ui.Sidebar };

            var logo = new RoundedPanel { Dock = DockStyle.Top, Height = 110, BorderVisible = false, BackColor = Ui.Sidebar };
            var sq = new RoundedPanel { Left = 20, Top = 34, Width = 42, Height = 42, Radius = 9, BackColor = Ui.Accent, BorderVisible = false };
            var sqTxt = new Label { Left = 0, Top = 5, Width = 42, Height = 32, TextAlign = ContentAlignment.MiddleCenter, Font = Ui.Face(11f, true), ForeColor = Color.FromArgb(20, 26, 12), Text = "NR" };
            sq.Controls.Add(sqTxt);
            var t1 = new Label { Left = 74, Top = 34, Width = 130, Height = 22, Font = Ui.Face(16f, true), ForeColor = Ui.Text, Text = "DLSS 5" };
            var t2 = new Label { Left = 74, Top = 58, Width = 130, Height = 18, Font = Ui.Face(9f, true), ForeColor = Ui.Accent, Text = "S W A P P E R" };
            logo.Controls.Add(sq);
            logo.Controls.Add(t1);
            logo.Controls.Add(t2);
            sidebar.Controls.Add(logo);

            var sep1 = new Panel { Dock = DockStyle.Top, Height = 1, BackColor = Ui.Border };
            sidebar.Controls.Add(sep1);

            var nav = new FlowLayoutPanel
            {
                Dock = DockStyle.Top,
                Height = 5 * 44 + 6,
                FlowDirection = FlowDirection.TopDown,
                WrapContents = false,
                Padding = new Padding(6, 6, 0, 0),
                BackColor = Ui.Sidebar
            };
            var items = new[]
            {
                new { key = "lib",  label = "Library",  glyph = "◈", page = "lib" },
                new { key = "opts", label = "Install",  glyph = "◉", page = "opts" },
                new { key = "bk",   label = "Backups",  glyph = "◀", page = "bkups" },
                new { key = "log",  label = "Console",  glyph = "≡", page = "log" },
                new { key = "abt",  label = "About",    glyph = "①", page = "about" }
            };
            for (int i = 0; i < items.Length; i++)
            {
                var nb = new Button
                {
                    Text = items[i].glyph + "  " + items[i].label,
                    Width = 202,
                    Height = 42,
                    FlatStyle = FlatStyle.Flat,
                    Font = Ui.Face(10f, false),
                    TextAlign = ContentAlignment.MiddleLeft,
                    Padding = new Padding(17, 0, 0, 0),
                    Cursor = Cursors.Hand,
                    BackColor = Ui.Sidebar,
                    ForeColor = Ui.Muted
                };
                nb.FlatAppearance.BorderSize = 0;
                nb.FlatAppearance.MouseOverBackColor = Color.FromArgb(30, 36, 50);
                nb.FlatAppearance.MouseDownBackColor = Color.FromArgb(22, 26, 38);
                string k = items[i].key, pg = items[i].page;
                nav.Controls.Add(nb);
                _nav[k] = nb;
                nb.Click += (s, e) => { Nav(k); ShowPage(pg); };
            }
            sidebar.Controls.Add(nav);

            var sep2 = new Panel { Dock = DockStyle.Top, Height = 1, BackColor = Ui.Border };
            sidebar.Controls.Add(sep2);

            var spacer = new Panel { Dock = DockStyle.Top, Height = 20, BackColor = Ui.Sidebar };
            sidebar.Controls.Add(spacer);

            var foot = new Label
            {
                Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft,
                Padding = new Padding(22, 0, 0, 18), Font = Ui.Face(8.5f, false), ForeColor = Ui.Muted,
                Text = "v2 · Deep Fried Chicken / RenoDX"
            };
            sidebar.Controls.Add(foot);

            Controls.Add(sidebar);
        }

        private void BuildContent()
        {
            var content = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Bg, Padding = new Padding(20, 10, 20, 12) };

            var head = new Panel { Dock = DockStyle.Top, Height = 62, BackColor = Ui.Bg };
            _pageTitle = new Label { AutoSize = false, Dock = DockStyle.Fill, TextAlign = ContentAlignment.BottomLeft, Font = Ui.Face(19f, true), ForeColor = Ui.Text };
            _pageSub = new Label { AutoSize = false, Dock = DockStyle.Bottom, Height = 20, TextAlign = ContentAlignment.MiddleLeft, Font = Ui.Face(9f, false), ForeColor = Ui.Muted };
            head.Controls.Add(_pageTitle);
            head.Controls.Add(_pageSub);
            content.Controls.Add(head);

            _pageHost = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Bg };
            content.Controls.Add(_pageHost);
            Controls.Add(content);

            BuildLibPage();
            BuildOptsPage();
            BuildBkPage();
            BuildLogPage();
            BuildAboutPage();
        }

        private void ShowPage(string key)
        {
            foreach (var kv in _pages) kv.Value.Visible = (kv.Key == key);
            switch (key)
            {
                case "lib": _pageTitle.Text = "Games library"; _pageSub.Text = "Folders you added, scanned for executables and renderer."; break;
                case "opts": _pageTitle.Text = "Install options"; _pageSub.Text = _selected == null
                        ? "Pick a game in the library first."
                        : _selected.Name + "  ·  " + _selected.Via;
                    if (_selected != null) SelectGame(_selected); break;
                case "bkups": _pageTitle.Text = "Backups & history"; _pageSub.Text = "Original files saved before an install - restore them anytime."; break;
                case "log": _pageTitle.Text = "Console"; _pageSub.Text = "Live output from the DLSS5 backend."; break;
                case "about": _pageTitle.Text = "About"; _pageSub.Text = ""; break;
            }
        }

        private void Nav(string key)
        {
            foreach (var kv in _nav)
            {
                kv.Value.BackColor = Ui.Sidebar;
                kv.Value.ForeColor = Ui.Muted;
                kv.Value.Font = Ui.Face(10f, false);
                kv.Value.FlatAppearance.MouseOverBackColor = Color.FromArgb(30, 36, 50);
                kv.Value.FlatAppearance.MouseDownBackColor = Color.FromArgb(22, 26, 38);
            }
            Button n;
            if (_nav.TryGetValue(key, out n))
            {
                n.BackColor = Ui.Accent;
                n.ForeColor = Color.FromArgb(18, 24, 10);
                n.Font = Ui.Face(10f, true);
                n.FlatAppearance.MouseOverBackColor = Ui.Accent;
                n.FlatAppearance.MouseDownBackColor = Ui.Accent;
            }
        }

        // ---------------------------------------------------------------- library page
        private void BuildLibPage()
        {
            var page = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Bg, Padding = new Padding(0, 0, 0, 0) };
            var toolbar = new RoundedPanel { Dock = DockStyle.Top, Height = 62, BackColor = Ui.Card, Padding = new Padding(14, 10, 14, 10) };
            _addFolderBtn = new FlatButton { Text = "+  Add game folder", Width = 150, Height = 34, Font = Ui.Face(9.5f, true), AutoSize = false };
            _addFolderBtn.SetColor(Ui.Accent);
            _addFolderBtn.Location = new Point(14, 13);
            _rescanBtn = new FlatButton { Text = "Rescan all", Width = 110, Height = 34, Font = Ui.Face(9.5f, true), AutoSize = false };
            _rescanBtn.SetColor(Ui.Blue);
            _rescanBtn.Location = new Point(172, 13);
            var hint = new Label { Left = 300, Top = 18, Width = 420, Height = 22, Font = Ui.Face(9f, false), ForeColor = Ui.Muted, Text = "Right-click actions on each card, or use Install / Options per game." };
            _libStatus = new Label { AutoSize = false, Dock = DockStyle.Bottom, Height = 28, TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(2, 0, 0, 0), Font = Ui.Face(9.5f, false), ForeColor = Ui.Muted, Text = "" };
            toolbar.Controls.Add(_addFolderBtn);
            toolbar.Controls.Add(_rescanBtn);
            toolbar.Controls.Add(hint);
            page.Controls.Add(toolbar);
            page.Controls.Add(_libStatus);

            _libFlow = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Ui.Bg, Padding = new Padding(0, 10, 0, 10), WrapContents = false };
            _libHint = new Label { AutoSize = false, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter, Font = Ui.Face(12f, true), ForeColor = Ui.Muted, Text = "No games yet.\n\nAdd a game folder - or drop a folder from Explorer onto this window." };
            page.Controls.Add(_libFlow);
            page.Controls.Add(_libHint);
            _pages["lib"] = page;
            _pageHost.Controls.Add(page);

            _libFlow.Resize += (s, e) =>
            {
                _libFlow.SuspendLayout();
                foreach (Control c in _libFlow.Controls)
                {
                    var card = c as GameCard;
                    if (card != null) card.Width = _libFlow.ClientSize.Width - 26;
                }
                _libFlow.ResumeLayout();
            };

            _libHint.AllowDrop = true;
            _libHint.DragEnter += (s, e) => { if (e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effect = DragDropEffects.Copy; };
            _libHint.DragDrop += (s, e) =>
            {
                var files = (string[])e.Data.GetData(DataFormats.FileDrop);
                if (files != null) foreach (var f in files) AddFolder(f);
            };
            _libFlow.DragEnter += _libHint_DragEnter;
            _libFlow.DragDrop += _libHint_DragDrop;

            _addFolderBtn.Click += (s, e) => AddFolderDialog();
            _rescanBtn.Click += (s, e) => RefreshLibrary(silent: false);
        }

        private void _libHint_DragEnter(object sender, DragEventArgs e)
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effect = DragDropEffects.Copy;
        }

        private void _libHint_DragDrop(object sender, DragEventArgs e)
        {
            var files = (string[])e.Data.GetData(DataFormats.FileDrop);
            if (files != null) foreach (var f in files) AddFolder(f);
        }

        private void AddFolderDialog()
        {
            using (var d = new FolderBrowserDialog { Description = "Select a game folder", ShowNewFolderButton = false })
            {
                if (d.ShowDialog() == DialogResult.OK) AddFolder(d.SelectedPath);
            }
        }

        private void AddFolder(string path)
        {
            try { path = Path.GetFullPath(path.Trim().Trim('"')).TrimEnd('\\'); } catch { return; }
            if (!Directory.Exists(path)) { Log("[warn] not a folder: " + path); return; }
            if (_folders.Contains(path, StringComparer.OrdinalIgnoreCase)) { Log("[warn] already added: " + path); return; }
            _folders.Add(path);
            SaveFolders();
            Log("+ folder: " + path);
            RefreshLibrary(silent: false);
        }

        private void LoadFolders()
        {
            try
            {
                if (!File.Exists(_settingsPath)) return;
                var js = new JavaScriptSerializer();
                var obj = js.Deserialize<Dictionary<string, object>>(File.ReadAllText(_settingsPath));
                var arr = obj != null && obj.ContainsKey("folders") ? obj["folders"] as ArrayList : null;
                if (arr == null) return;
                foreach (object o in arr)
                {
                    var s = o as string;
                    if (s != null && Directory.Exists(s) && !_folders.Contains(s, StringComparer.OrdinalIgnoreCase))
                        _folders.Add(s);
                }
            }
            catch { }
        }

        private void SaveFolders()
        {
            try
            {
                var js = new JavaScriptSerializer();
                File.WriteAllText(_settingsPath, js.Serialize(new Dictionary<string, object> { { "folders", _folders.ToArray() } }));
            }
            catch { }
        }

        private void RefreshLibrary(bool silent)
        {
            _library.Clear();
            RebuildCards();
            if (_folders.Count == 0) { ShowLibEmpty(); return; }
            SetStatus(silent, _folders.Count + " folder" + (_folders.Count == 1 ? "" : "s") + " - scanning...");
            _rescanBtn.Enabled = false;
            _addFolderBtn.Enabled = false;
            var folders = new List<string>(_folders);
            ThreadPool.QueueUserWorkItem(delegate
            {
                for (int i = 0; i < folders.Count; i++)
                {
                    var list = ScanFolder(folders[i]);
                    BeginInvoke(new Action(delegate
                    {
                        _library.AddRange(list);
                        RebuildCards();
                        SetStatus(false, "Scanned " + folders[i] + "  (" + (i + 1) + "/" + folders.Count + ")");
                    }));
                }
                BeginInvoke(new Action(delegate
                {
                    _rescanBtn.Enabled = true;
                    _addFolderBtn.Enabled = true;
                    SetStatus(false, _folders.Count + " folder" + (_folders.Count == 1 ? "" : "s") + ", " + _library.Count +
                        " executable" + (_library.Count == 1 ? "" : "s") + " found. Click a game → Install.");
                    if (_library.Count == 0) ShowLibEmpty();
                }));
            });
        }

        private void ShowLibEmpty()
        {
            _libFlow.SuspendLayout();
            _libFlow.Controls.Clear();
            _libFlow.ResumeLayout();
            _libHint.Visible = true;
        }

        private void SetStatus(bool silent, string text)
        {
            if (silent) return;
            _libStatus.Text = text;
        }

        private List<GameInfo> ScanFolder(string dir)
        {
            var result = new List<GameInfo>();
            try
            {
                var dict = RunPs("-Scan -Json -GamePath \"" + dir + "\"");
                if (dict == null) return result;
                var cands = dict.ContainsKey("candidates") ? dict["candidates"] as ArrayList : null;
                bool native = dict.ContainsKey("hasNativeDlss") && Convert.ToBoolean(dict["hasNativeDlss"]);
                string reshText = "none";
                bool resh = false;
                var reshObj = dict.ContainsKey("reshade") ? dict["reshade"] as Dictionary<string, object> : null;
                if (reshObj != null && reshObj.ContainsKey("present"))
                {
                    bool.TryParse(reshObj["present"].ToString(), out resh);
                    if (resh) reshText = (reshObj.ContainsKey("file") ? reshObj["file"] : "?") + " v" + (reshObj.ContainsKey("version") ? reshObj["version"] : "?");
                }
                if (cands == null) return result;
                foreach (object c in cands)
                {
                    var d = c as Dictionary<string, object>;
                    if (d == null) continue;
                    var gi = new GameInfo
                    {
                        Dir = dir,
                        Path = Str(d, "Path"),
                        Name = Str(d, "Name"),
                        Bitness = Str(d, "Bitness"),
                        Api = Str(d, "Api"),
                        Label = Str(d, "Label"),
                        Via = Str(d, "Via"),
                        HasNative = native,
                        ReshadePresent = resh,
                        ReshadeText = reshText
                    };
                    if (gi.Name.Length == 0) continue;
                    result.Add(gi);
                }
                Log("scan ok: " + Path.GetFileName(dir) + " (" + result.Count + " exe)");
            }
            catch (Exception ex) { Log("[error] scan " + dir + ": " + ex.Message); }
            return result;
        }

        private static string Str(Dictionary<string, object> d, string key)
        {
            if (d.ContainsKey(key) && d[key] != null) return d[key].ToString();
            return "";
        }

        private void RebuildCards()
        {
            _libFlow.SuspendLayout();
            _libFlow.Controls.Clear();
            foreach (var gi in _library)
            {
                var card = new GameCard(gi);
                card.Width = _libFlow.ClientSize.Width - 26;
                if (card.Width < 300) card.Width = 300;
                card.Margin = new Padding(0, 0, 0, 8);
                card.OnSelect += SelectGame;
                card.OnInstall += delegate { SelectGame(gi); RunBackend("Install", gi.Dir, gi.Name, null); };
                card.OnVerify += delegate { SelectGame(gi); RunBackend("Verify", gi.Dir, gi.Name, null); };
                card.OnUninstall += delegate { SelectGame(gi); RunBackend("Uninstall", gi.Dir, gi.Name, OnUninstalled); };
                card.OnOpen += delegate { try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + gi.Path + "\"") { UseShellExecute = true }); } catch { } };
                _libFlow.Controls.Add(card);
            }
            _libFlow.ResumeLayout();
            _libHint.Visible = _library.Count == 0;
        }

        private void OnUninstalled(Dictionary<string, object> dict)
        {
            if (dict != null)
                Log("== uninstall: removed=" + (((ArrayList)dict["removed"]).Count) + " restored=" + (((ArrayList)dict["restored"]).Count));
            RefreshLibrary(silent: true);
        }

        private void SelectGame(GameInfo gi)
        {
            _selected = gi;
            foreach (Control c in _libFlow.Controls)
            {
                var card = c as GameCard;
                if (card != null) card.Selected = ReferenceEquals(card.Info, gi);
            }
            _optTitle.Text = gi.Name + (gi.Bitness.Length == 0 ? "" : "   (" + gi.Bitness + "-bit)");
            _optBadge.Text = gi.Undetected ? "RENDERER UNKNOWN" : (gi.Label.ToUpper() + "  ·  " + gi.Via.ToUpper());
            _optBadge.Width = ((int)(_optBadge.Text.Length * 7.6f) + 24);
            _optBadge.Fill = gi.Undetected ? Ui.DangerDim : Ui.AccentDim;
            _optBadge.TextColor = gi.Undetected ? Ui.Danger : Ui.Accent;
            _optHint.Text = gi.Dir + (gi.HasNative ? "   ·   native DLSS present" : "") +
                            (gi.ReshadePresent ? "   ·   ReShade " + gi.ReshadeText : "");
            _apiNote.Text = gi.Undetected
                ? "Renderer could not be auto-detected - set Force render API above."
                : "";
            _apiNote.ForeColor = gi.Undetected ? Ui.Gold : Ui.Muted;
            RefreshOptionAvailability();
        }

        // ---------------------------------------------------------------- options page
        private void BuildOptsPage()
        {
            var page = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Bg };

            var sec = new RoundedPanel { Dock = DockStyle.Top, Height = 92, BackColor = Ui.Card, Margin = new Padding(0, 0, 0, 10) };
            _optTitle = new Label { Dock = DockStyle.Top, Height = 26, Padding = new Padding(16, 8, 0, 0), TextAlign = ContentAlignment.MiddleLeft, Font = Ui.Face(13f, true), ForeColor = Ui.Text, Text = "No game selected" };
            _optBadge = new Pill { Text = "     ", Height = 22, Location = new Point(16, 40) };
            _optHint = new Label { AutoSize = false, Dock = DockStyle.Bottom, Height = 24, Padding = new Padding(16, 0, 0, 0), TextAlign = ContentAlignment.MiddleLeft, Font = Ui.Face(9f, false), ForeColor = Ui.Muted };
            sec.Controls.Add(_optTitle);
            sec.Controls.Add(_optBadge);
            sec.Controls.Add(_optHint);
            page.Controls.Add(sec);

            var body = new RoundedPanel { Dock = DockStyle.Fill, BackColor = Ui.Card, Padding = new Padding(20, 12, 20, 12) };
            var grid = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, RowCount = 7, Padding = new Padding(0) };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 32));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 22));

            var providerLbl = Sect("NEURAL PROVIDER");
            grid.Controls.Add(providerLbl, 0, 0);
            grid.SetColumnSpan(providerLbl, 4);

            _segChicken = new FlatButton { Text = "Deep Fried Chicken", AutoSize = false, Height = 30, Dock = DockStyle.Top };
            _segChicken.SetColor(Ui.Accent);
            _segRenodx = new FlatButton { Text = "RenoDX", AutoSize = false, Height = 30, Dock = DockStyle.Top };
            _segRenodx.SetColor(Ui.CardHi);
            var provPanel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(0, 2, 0, 0) };
            provPanel.Controls.Add(_segChicken);
            var provPanel2 = new Panel { Dock = DockStyle.Fill, Padding = new Padding(0, 2, 0, 0) };
            provPanel2.Controls.Add(_segRenodx);
            grid.Controls.Add(provPanel, 0, 1);
            grid.Controls.Add(provPanel2, 1, 1);

            var passLbl = Field("Passes (multi-pass)");
            _passes = Num(1, 30, 1);
            var workLbl = Field("Work resolution %");
            _workRes = Num(10, 150, 100);
            grid.Controls.Add(passLbl, 0, 2);
            grid.Controls.Add(_passes, 1, 2);
            grid.Controls.Add(workLbl, 2, 2);
            grid.Controls.Add(_workRes, 3, 2);

            var styleLbl = Field("Quality style");
            _styleBox = Combo("default", "natural", "cinematic");
            var presetLbl = Field("NR preset (0-3)");
            _presetBox = Num(0, 3, 0);
            grid.Controls.Add(styleLbl, 0, 3);
            grid.Controls.Add(_styleBox, 1, 3);
            grid.Controls.Add(presetLbl, 2, 3);
            grid.Controls.Add(_presetBox, 3, 3);

            var mvLbl = Field("Motion-vector provider");
            _mvBox = Combo("0 - texMotionVectors", "1 - Launchpad", "2 - VORT", "3 - Lumenite Kernel", "4 - QuantMotion");
            _mvBox.SelectedIndex = 3;
            var intenLbl = Field("NR intensity");
            _intensityBox = NumIntensity();
            grid.Controls.Add(mvLbl, 0, 4);
            grid.Controls.Add(_mvBox, 1, 4);
            grid.Controls.Add(intenLbl, 2, 4);
            grid.Controls.Add(_intensityBox, 3, 4);

            var apiLbl = Field("Force render API");
            _apiBox = Combo("auto", "d3d12", "d3d11", "d3d10", "dxgi", "vulkan", "d3d9", "d3d8", "opengl");
            var feederLbl = Field("Feeder mode");
            _feederBox = Combo("auto", "forced", "off");
            grid.Controls.Add(apiLbl, 0, 5);
            grid.Controls.Add(_apiBox, 1, 5);
            grid.Controls.Add(feederLbl, 2, 5);
            grid.Controls.Add(_feederBox, 3, 5);

            var toggles = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(0, 14, 0, 0), WrapContents = false };
            _cleanFry = Toggle("  Clean Fry (multi-pass)");
            _texBoost = Toggle("  Texture Boost (8K)");
            _uplift = Toggle("  NeuralUplift");
            _launch = Toggle("  Launch game after install");
            _dryRun = Toggle("  Dry run");
            _force = Toggle("  Force (skip safety checks)");
            toggles.Controls.Add(_cleanFry);
            toggles.Controls.Add(_texBoost);
            toggles.Controls.Add(_uplift);
            toggles.Controls.Add(_launch);
            toggles.Controls.Add(_dryRun);
            toggles.Controls.Add(_force);
            grid.Controls.Add(toggles, 0, 6);
            grid.SetColumnSpan(toggles, 4);

            body.Controls.Add(grid);
            page.Controls.Add(body);

            var bar = new RoundedPanel { Dock = DockStyle.Bottom, Height = 66, BackColor = Ui.Card, Padding = new Padding(14, 12, 14, 10) };
            var install = new FlatButton { Text = "Install", AutoSize = false, Width = 150, Height = 36, Font = Ui.Face(10f, true) };
            install.SetColor(Ui.Accent);
            install.Location = new Point(14, 14);
            var verify = new FlatButton { Text = "Verify", AutoSize = false, Width = 110, Height = 36, Font = Ui.Face(10f, true) };
            verify.SetColor(Ui.Blue);
            verify.Location = new Point(172, 14);
            var uninst = new FlatButton { Text = "Uninstall", AutoSize = false, Width = 110, Height = 36, Font = Ui.Face(10f, true) };
            uninst.SetColor(Ui.Danger);
            uninst.Location = new Point(290, 14);
            var open = new FlatButton { Text = "Open folder", AutoSize = false, Width = 110, Height = 36, Font = Ui.Face(10f, true) };
            open.SetColor(Ui.Muted);
            open.Location = new Point(408, 14);
            _optInstall = install;
            _optVerify = verify;
            _optUninst = uninst;
            _apiNote = new Label { AutoSize = false, Left = 530, Top = 20, Width = 430, Height = 24, Font = Ui.Face(9f, false), ForeColor = Ui.Gold, Text = "" };
            bar.Controls.Add(install);
            bar.Controls.Add(verify);
            bar.Controls.Add(uninst);
            bar.Controls.Add(open);
            bar.Controls.Add(_apiNote);
            page.Controls.Add(bar);
            page.Controls.Add(sec);
            page.Controls.Add(body);

            _pages["opts"] = page;
            _pageHost.Controls.Add(page);

            _segChicken.Click += (s, e) => SetProvider(true);
            _segRenodx.Click += (s, e) => SetProvider(false);
            install.Click += (s, e) => { if (_selected == null) { Log("[warn] pick a game in the library first."); ShowPage("lib"); return; } RunBackend("Install", _selected.Dir, _selected.Name, null); };
            verify.Click += (s, e) => { if (_selected == null) { Log("[warn] pick a game in the library first."); ShowPage("lib"); return; } RunBackend("Verify", _selected.Dir, _selected.Name, null); };
            uninst.Click += (s, e) => { if (_selected == null) { Log("[warn] pick a game in the library first."); ShowPage("lib"); return; } RunBackend("Uninstall", _selected.Dir, _selected.Name, OnUninstalled); };
            open.Click += (s, e) => { if (_selected == null) return; try { Process.Start(new ProcessStartInfo("explorer.exe", "\"" + _selected.Dir + "\"") { UseShellExecute = true }); } catch { } };
        }

        private Label Sect(string t) { return new Label { Text = t, Height = 22, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, Font = Ui.Face(9f, true), ForeColor = Ui.Accent, Padding = new Padding(0, 4, 0, 0) }; }
        private Label Field(string t) { return new Label { Text = t, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, Font = Ui.Face(9f, false), ForeColor = Ui.Muted }; }
        private CheckBox Toggle(string t) { return new CheckBox { Text = t, AutoSize = true, Margin = new Padding(0, 0, 22, 0), ForeColor = Ui.Text, Font = Ui.Face(9f, false) }; }

        private NumericUpDown Num(decimal min, decimal max, decimal val)
        {
            var n = new NumericUpDown { Minimum = min, Maximum = max, Value = val, Width = 130, Height = 28, BackColor = Ui.Bg, ForeColor = Ui.Text, BorderStyle = BorderStyle.FixedSingle, TextAlign = HorizontalAlignment.Center };
            return n;
        }

        private NumericUpDown NumIntensity()
        {
            var n = Num(1, 4, 2);
            n.DecimalPlaces = 1;
            n.Increment = 0.5m;
            return n;
        }

        private ComboBox Combo(params string[] items)
        {
            var c = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 130, Height = 28, BackColor = Ui.Bg, ForeColor = Ui.Text, FlatStyle = FlatStyle.Flat };
            c.Items.AddRange(items);
            c.SelectedIndex = 0;
            return c;
        }

        private bool IsChicken() { return _segChicken.BackColor == Ui.Accent; }

        private void SetProvider(bool chicken)
        {
            if (chicken)
            {
                _segChicken.SetColor(Ui.Accent);
                _segRenodx.SetColor(Ui.CardHi);
            }
            else
            {
                _segChicken.SetColor(Ui.CardHi);
                _segRenodx.SetColor(Ui.Accent);
            }
            RefreshOptionAvailability();
        }

        private void RefreshOptionAvailability()
        {
            bool chicken = IsChicken();
            _passes.Enabled = chicken;
            _cleanFry.Enabled = chicken;
            _texBoost.Enabled = chicken;
            _uplift.Enabled = true;
            _passes.ForeColor = chicken ? Ui.Text : Ui.Muted;
            _cleanFry.ForeColor = chicken ? Ui.Text : Ui.Muted;
            _texBoost.ForeColor = chicken ? Ui.Text : Ui.Muted;
        }

        // ---------------------------------------------------------------- backups page
        private void BuildBkPage()
        {
            var page = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Bg };
            var toolbar = new RoundedPanel { Dock = DockStyle.Top, Height = 52, BackColor = Ui.Card, Padding = new Padding(14, 10, 14, 10) };
            var refresh = new FlatButton { Text = "Refresh backups", AutoSize = false, Width = 140, Height = 32, Font = Ui.Face(9.5f, true) };
            refresh.SetColor(Ui.Blue);
            refresh.Location = new Point(14, 9);
            _bkStatus = new Label { AutoSize = false, Left = 170, Top = 14, Width = 500, Height = 22, Font = Ui.Face(9f, false), ForeColor = Ui.Muted, Text = "" };
            toolbar.Controls.Add(refresh);
            toolbar.Controls.Add(_bkStatus);
            page.Controls.Add(toolbar);

            _bkFlow = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Ui.Bg, Padding = new Padding(0, 10, 0, 10), WrapContents = false };
            page.Controls.Add(_bkFlow);
            _pages["bkups"] = page;
            _pageHost.Controls.Add(page);
            refresh.Click += (s, e) => RefreshBackups();
        }

        private void RefreshBackups()
        {
            _bkFlow.SuspendLayout();
            _bkFlow.Controls.Clear();
            _bkFlow.ResumeLayout();
            _bkStatus.Text = "Scanning folders for backups...";
            var folders = new List<string>(_folders);
            ThreadPool.QueueUserWorkItem(delegate
            {
                var found = new List<BackupEntry>();
                foreach (var dir in folders)
                {
                    try
                    {
                        var m = Path.Combine(dir, "_DLSS5_Backup", "manifest.json");
                        if (!File.Exists(m)) continue;
                        int entries = 0;
                        try { entries = new JavaScriptSerializer().Deserialize<ArrayList>(File.ReadAllText(m)).Count; } catch { }
                        found.Add(new BackupEntry { Dir = dir, Entries = entries });
                    }
                    catch { }
                }
                BeginInvoke(new Action(delegate
                {
                    _bkFlow.SuspendLayout();
                    _bkFlow.Controls.Clear();
                    foreach (var b in found)
                    {
                        var card = new BackupCard(b.Dir, b.Entries);
                        card.Width = _bkFlow.ClientSize.Width - 26;
                        if (card.Width < 300) card.Width = 300;
                        card.Margin = new Padding(0, 0, 0, 8);
                        card.OnRestore += delegate { RunBackend("Uninstall", b.Dir, "", null); RefreshBackups(); };
                        card.OnOpen += delegate { try { Process.Start(new ProcessStartInfo("explorer.exe", b.Dir) { UseShellExecute = true }); } catch { } };
                        _bkFlow.Controls.Add(card);
                    }
                    _bkFlow.ResumeLayout();
                    _bkStatus.Text = found.Count + " backup" + (found.Count == 1 ? "" : "s") + " found.";
                }));
            });
        }

        private class BackupEntry { public string Dir; public int Entries; }

        // ---------------------------------------------------------------- log page
        private void BuildLogPage()
        {
            var page = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Bg };
            _log = new TextBox
            {
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Both,
                Dock = DockStyle.Fill,
                BackColor = Color.FromArgb(9, 11, 16),
                ForeColor = Ui.Text,
                BorderStyle = BorderStyle.None,
                Font = new Font("Consolas", 9.5f)
            };
            var bar = new RoundedPanel { Dock = DockStyle.Top, Height = 52, BackColor = Ui.Card, Padding = new Padding(14, 9, 14, 9) };
            _copyLogBtn = new FlatButton { Text = "Copy", AutoSize = false, Width = 90, Height = 32, Font = Ui.Face(9.5f, true) };
            _copyLogBtn.SetColor(Ui.Muted);
            _copyLogBtn.Location = new Point(14, 9);
            _clearLogBtn = new FlatButton { Text = "Clear", AutoSize = false, Width = 90, Height = 32, Font = Ui.Face(9.5f, true) };
            _clearLogBtn.SetColor(Ui.Muted);
            _clearLogBtn.Location = new Point(112, 9);
            bar.Controls.Add(_copyLogBtn);
            bar.Controls.Add(_clearLogBtn);
            page.Controls.Add(_log);
            page.Controls.Add(bar);
            _pages["log"] = page;
            _pageHost.Controls.Add(page);
            _copyLogBtn.Click += (s, e) => { try { System.Windows.Forms.Clipboard.SetText(_log.Text); } catch { } };
            _clearLogBtn.Click += (s, e) => _log.Clear();
        }

        // ---------------------------------------------------------------- about page
        private void BuildAboutPage()
        {
            var page = new Panel { Dock = DockStyle.Fill, BackColor = Ui.Bg };
            var card = new RoundedPanel { BackColor = Ui.Card, Width = 560, Height = 320, Anchor = AnchorStyles.None };
            page.Resize += (s, e) => { card.Left = (page.ClientSize.Width - card.Width) / 2; card.Top = 40; };
            card.Left = (page.ClientSize.Width - card.Width) / 2;
            card.Top = 40;

            var sq = new RoundedPanel { Left = 30, Top = 28, Width = 54, Height = 54, Radius = 12, BackColor = Ui.Accent, BorderVisible = false };
            var sqTxt = new Label { Left = 0, Top = 8, Width = 54, Height = 38, TextAlign = ContentAlignment.MiddleCenter, Font = Ui.Face(13f, true), ForeColor = Color.FromArgb(20, 26, 12), Text = "DLSS\n5" };
            sq.Controls.Add(sqTxt);

            var title = new Label { Left = 100, Top = 28, Width = 420, Height = 28, Font = Ui.Face(17f, true), ForeColor = Ui.Text, Text = "DLSS 5 Swapper" };
            var ver = new Label { Left = 100, Top = 58, Width = 420, Height = 20, Font = Ui.Face(9f, false), ForeColor = Ui.Accent, Text = "wizard 2.0  ·  Deep Fried Chicken / RenoDX  ·  DLSS5-Feeder" };
            var body = new Label
            {
                Left = 30, Top = 104, Width = 500, Height = 130, Font = Ui.Face(9f, false), ForeColor = Ui.Muted,
                Text = "Installs the DLSS 5 neural-rendering stack into games and emulators.\n" +
                       "The wizard drives DLSS5-Swapper.ps1 ; the two share the same options.\n\n" +
                       "Features:\n" +
                       "  · automatic renderer detection (DirectX 9/10/11/12, Vulkan, OpenGL, Unity)\n" +
                       "  · Deep Fried Chicken multi-pass configurator + RenoDX single-pass\n" +
                       "  · DLSS5-Feeder for titles without native DLSS\n" +
                       "  · backups: originals are stored and can be restored any time"
            };
            var links = new Label { Left = 30, Top = 246, Width = 500, Height = 40, Font = Ui.Face(9f, false), ForeColor = Ui.Blue, Text = "github.com/PaulAchitei/DLSS5   ·   rebuild: powershell .\\Build-UI.ps1", Cursor = Cursors.Hand };
            links.Click += (s, e) => { try { Process.Start("https://github.com/PaulAchitei/DLSS5"); } catch { } };

            card.Controls.Add(sq);
            card.Controls.Add(title);
            card.Controls.Add(ver);
            card.Controls.Add(body);
            card.Controls.Add(links);
            page.Controls.Add(card);
            _pages["about"] = page;
            _pageHost.Controls.Add(page);
        }

        // ---------------------------------------------------------------- backend
        private Dictionary<string, object> RunPs(string args)
        {
            var psi = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = _appDir,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + _scriptPath + "\" " + args
            };
            using (var p = Process.Start(psi))
            {
                var so = new StringBuilder();
                p.OutputDataReceived += (s, e) => { if (e.Data != null) so.AppendLine(e.Data); };
                p.ErrorDataReceived += (s, e) => { if (e.Data != null) Log(e.Data); };
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                p.WaitForExit();
                var text = so.ToString().Trim();
                if (text.Length == 0) return null;
                var js = new JavaScriptSerializer();
                try { return js.Deserialize<Dictionary<string, object>>(text); }
                catch
                {
                    Log("[warning] unparsed backend output: " + text.Substring(0, Math.Min(text.Length, 400)));
                    return null;
                }
            }
        }

        private string BuildArgs(string action, string dir, string exe)
        {
            var sb = new StringBuilder("-" + action + " -Json -GamePath \"" + dir + "\"");
            if (!string.IsNullOrEmpty(exe)) sb.Append(" -Exe \"").Append(exe).Append("\"");
            sb.Append(" -Provider ").Append(IsChicken() ? "chicken" : "renodx");
            sb.Append(" -Passes ").Append(((int)_passes.Value));
            sb.Append(" -WorkResolution ").Append(((int)_workRes.Value));
            if (_styleBox.SelectedIndex >= 0) sb.Append(" -Style ").Append(_styleBox.SelectedItem);
            sb.Append(" -Preset ").Append(((int)_presetBox.Value));
            sb.Append(" -Intensity ").Append(((double)_intensityBox.Value).ToString(CultureInfo.InvariantCulture));
            if (_mvBox.SelectedIndex >= 0) sb.Append(" -MVProvider ").Append(_mvBox.SelectedIndex);
            if (_feederBox.SelectedIndex > 0) sb.Append(" -Feeder ").Append(_feederBox.SelectedItem);
            if (_apiBox.SelectedIndex > 0) sb.Append(" -Api ").Append(_apiBox.SelectedItem);
            if (_cleanFry.Checked && _cleanFry.Enabled) sb.Append(" -CleanFry");
            if (_texBoost.Checked && _texBoost.Enabled) sb.Append(" -TextureBoost");
            if (_uplift.Checked) sb.Append(" -NeuralUplift");
            if (_dryRun.Checked) sb.Append(" -DryRun");
            if (_force.Checked) sb.Append(" -Force");
            if (_launch.Checked) sb.Append(" -Launch");
            return sb.ToString();
        }

        private void RunBackend(string action, string dir, string exe, Action<Dictionary<string, object>> onDone)
        {
            if (_busy) { Log("[warn] an operation is already running."); return; }
            if (!File.Exists(_scriptPath)) { Log("[error] DLSS5-Swapper.ps1 missing next to this program."); return; }
            _busy = true;
            SetBusy(false);
            Log(">> " + action + " " + Path.GetFileName(dir.TrimEnd('\\')) + " ...");

            string args = BuildArgs(action, dir, exe);
            ThreadPool.QueueUserWorkItem(delegate
            {
                Dictionary<string, object> dict = null;
                try { dict = RunPs(args); }
                catch (Exception ex) { BeginInvoke(new Action(delegate { Log("[error] " + ex.Message); })); }
                var d = dict;
                BeginInvoke(new Action(delegate
                {
                    try
                    {
                        if (d == null) { Log("== backend produced no result (see errors above)."); }
                        else if (action == "Install")
                        {
                            var files = d.ContainsKey("added") && d["added"] is ArrayList ? ((ArrayList)d["added"]).Count : 0;
                            Log("== installed: provider=" + d["provider"] + " api=" + d["api"] + " feeder=" + d["feeder"] +
                                " files=" + files + " dryRun=" + d["dryRun"]);
                        }
                        else if (action == "Verify")
                        {
                            var checks = d.ContainsKey("checks") ? d["checks"] as ArrayList : null;
                            if (checks != null)
                                foreach (object c in checks)
                                {
                                    var ck = c as Dictionary<string, object>;
                                    if (ck == null) continue;
                                    bool ok = false;
                                    if (ck.ContainsKey("Ok") && ck["Ok"] != null) bool.TryParse(ck["Ok"].ToString(), out ok);
                                    Log("   [" + (ok ? "OK" : "FAIL") + "] " + Str(ck, "Item") + "  " + Str(ck, "Note"));
                                }
                        }
                    }
                    catch (Exception ex) { Log("[error] " + ex.Message); }
                    if (onDone != null) { try { onDone(d); } catch (Exception ex) { Log("[error] " + ex.Message); } }
                    SetBusy(true);
                    _busy = false;
                }));
            });
        }

        private void SetBusy(bool idle)
        {
            _rescanBtn.Enabled = idle;
            _addFolderBtn.Enabled = idle;
            if (_optInstall != null)
            {
                _optInstall.Enabled = idle && _selected != null;
                _optVerify.Enabled = idle && _selected != null;
                _optUninst.Enabled = idle && _selected != null;
            }
            UseWaitCursor = !idle;
        }

        private void Log(string line)
        {
            if (InvokeRequired) { BeginInvoke(new Action<string>(Log), line); return; }
            if (_log == null) return;
            _log.AppendText(line + "\r\n");
            _log.SelectionStart = _log.TextLength;
            _log.ScrollToCaret();
        }

        [STAThread]
        public static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new WizardForm());
        }
    }
}