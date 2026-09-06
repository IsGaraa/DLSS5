using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace DLSS5
{
    public class WizardForm : Form
    {
        private readonly string _appDir;
        private readonly string _scriptPath;
        private readonly List<Dictionary<string, object>> _candidates = new List<Dictionary<string, object>>();

        // Step 1 - game folder
        private TextBox _gameDirBox;
        private Button _browseBtn;
        private Button _scanBtn;
        private ListView _gameList;
        private Label _scanSummary;

        // Step 2 - options
        private RadioButton _rbChicken;
        private RadioButton _rbRenodx;
        private NumericUpDown _passes;
        private NumericUpDown _workRes;
        private ComboBox _styleBox;
        private NumericUpDown _presetBox;
        private NumericUpDown _intensityBox;
        private ComboBox _mvBox;
        private CheckBox _cleanFry;
        private CheckBox _texBoost;
        private CheckBox _uplift;
        private ComboBox _feederBox;
        private ComboBox _apiBox;
        private CheckBox _dryRun;
        private CheckBox _force;
        private CheckBox _launch;

        // Step 3 - actions
        private Button _installBtn;
        private Button _verifyBtn;
        private Button _uninstallBtn;
        private TextBox _log;
        private Button _closeBtn;

        public WizardForm()
        {
            _appDir = Path.GetDirectoryName(Application.ExecutablePath);
            _scriptPath = Path.Combine(_appDir, "DLSS5-Swapper.ps1");

            Text = "DLSS 5 Swapper";
            Font = new Font("Segoe UI", 9f);
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(860, 620);

            BuildUi();
            if (!File.Exists(_scriptPath))
                MessageBox.Show("DLSS5-Swapper.ps1 not found next to this program.", "DLSS 5 Swapper",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            else if (!Directory.Exists(Path.Combine(_appDir, "kit")))
                Log("[notice] kit/ not built - the first Install will run -BuildKit automatically.\r\n");
        }

        private void BuildUi()
        {
            var header = new Label
            {
                Dock = DockStyle.Top,
                Height = 30,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = new Font("Segoe UI", 11f, FontStyle.Bold),
                Text = "  DLSS 5 Swapper - install DLSS 5 (Deep Fried Chicken / RenoDX) into any game"
            };
            Controls.Add(header);

            _log = new TextBox
            {
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Both,
                Dock = DockStyle.Fill,
                BackColor = Color.FromArgb(12, 12, 18),
                ForeColor = Color.FromArgb(220, 220, 220),
                Font = new Font("Consolas", 9f)
            };

            var actions = new TableLayoutPanel
            {
                Dock = DockStyle.Bottom,
                Height = 78,
                ColumnCount = 5,
                Padding = new Padding(8, 4, 8, 8)
            };
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 20));
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 20));
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 20));
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 20));
            actions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 20));
            _installBtn = MkButton("Install", Color.FromArgb(28, 130, 80));
            _verifyBtn = MkButton("Verify", Color.FromArgb(36, 90, 180));
            _uninstallBtn = MkButton("Uninstall", Color.FromArgb(150, 60, 60));
            _closeBtn = MkButton("Close", Color.FromArgb(80, 80, 80));
            actions.Controls.Add(_installBtn, 0, 0);
            actions.Controls.Add(_verifyBtn, 1, 0);
            actions.Controls.Add(_uninstallBtn, 2, 0);
            actions.Controls.Add(_closeBtn, 4, 0);
            var status = new Label
            {
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleCenter,
                ForeColor = Color.DimGray,
                Text = "scans the Windows way"
            };
            actions.Controls.Add(status, 3, 0);
            _installBtn.Click += (s, e) => RunAction("Install");
            _verifyBtn.Click += (s, e) => RunAction("Verify");
            _uninstallBtn.Click += (s, e) => RunAction("Uninstall");
            _closeBtn.Click += (s, e) => Close();
            Controls.Add(_log);
            Controls.Add(actions);

            BuildOptionsPanel();
            BuildFolderPanel();
        }

        private void BuildFolderPanel()
        {
            var p = new Panel { Dock = DockStyle.Top, Height = 196, Padding = new Padding(10, 6, 10, 4) };
            var row = new TableLayoutPanel { Dock = DockStyle.Top, Height = 34, ColumnCount = 4 };
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 78));
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 98));
            _gameDirBox = new TextBox { Dock = DockStyle.Fill };
            _browseBtn = new Button { Text = "Browse..." };
            _scanBtn = new Button { Text = "Scan folder", BackColor = Color.FromArgb(50, 110, 180) };
            row.Controls.Add(new Label { Text = "Game folder", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 0);
            row.Controls.Add(_gameDirBox, 1, 0);
            row.Controls.Add(_browseBtn, 2, 0);
            row.Controls.Add(_scanBtn, 3, 0);
            p.Controls.Add(row);

            _gameList = new ListView
            {
                View = View.Details,
                FullRowSelect = true,
                Dock = DockStyle.Fill,
                HeaderStyle = ColumnHeaderStyle.Nonclickable
            };
            _gameList.Columns.Add("Executable", 300);
            _gameList.Columns.Add("Bits", 46);
            _gameList.Columns.Add("Render API", 150);
            _gameList.Columns.Add("Detected via", 130);
            p.Controls.Add(_gameList);
            p.Controls.Add(new Label
            {
                Text = "Detected games (select the main executable)",
                Dock = DockStyle.Top,
                Height = 22,
                Padding = new Padding(0, 2, 0, 0)
            });

            _scanSummary = new Label
            {
                Dock = DockStyle.Bottom,
                Height = 30,
                TextAlign = ContentAlignment.MiddleLeft,
                AutoEllipsis = true,
                ForeColor = Color.DimGray
            };
            p.Controls.Add(_scanSummary);
            Controls.Add(p);

            _browseBtn.Click += (s, e) =>
            {
                using (var d = new FolderBrowserDialog { Description = "Select the game folder" })
                {
                    if (d.ShowDialog() == DialogResult.OK) _gameDirBox.Text = d.SelectedPath;
                }
            };
            _scanBtn.Click += (s, e) => DoScan();
        }

        private void BuildOptionsPanel()
        {
            var g = new GroupBox { Text = "Install options", Dock = DockStyle.Top, Height = 184, Padding = new Padding(10, 8, 10, 4) };

            var providerLbl = new Label { Top = 20, Left = 14, Width = 90, Text = "Neural provider" };
            _rbChicken = new RadioButton { Top = 36, Left = 14, Width = 150, Text = "Deep Fried Chicken", Checked = true };
            _rbRenodx = new RadioButton { Top = 36, Left = 170, Width = 160, Text = "RenoDX (single pass)" };

            _passes = new NumericUpDown { Top = 58, Left = 110, Width = 50, Minimum = 1, Maximum = 30, Value = 1 };
            var passLbl = new Label { Top = 61, Left = 14, Width = 92, Text = "Passes (1-30)" };
            _workRes = new NumericUpDown { Top = 58, Left = 300, Width = 52, Minimum = 10, Maximum = 150, Value = 100 };
            var workLbl = new Label { Top = 61, Left = 170, Width = 120, Text = "Work resolution %" };
            _styleBox = new ComboBox
            {
                Top = 58,
                Left = 410,
                Width = 112,
                DropDownStyle = ComboBoxStyle.DropDownList,
                Items = { "default", "natural", "cinematic" }
            };
            _styleBox.SelectedIndex = 0;
            var styleLbl = new Label { Top = 61, Left = 366, Width = 42, Text = "Style" };
            _mvBox = new ComboBox
            {
                Top = 58,
                Left = 640,
                Width = 198,
                DropDownStyle = ComboBoxStyle.DropDownList,
                Items = { "0 - texMotionVectors", "1 - Launchpad", "2 - VORT", "3 - Lumenite Kernel", "4 - QuantMotion" }
            };
            _mvBox.SelectedIndex = 3;
            var mvLbl = new Label { Top = 61, Left = 550, Width = 88, Text = "MV provider" };

            _presetBox = new NumericUpDown { Top = 88, Left = 110, Width = 50, Minimum = 0, Maximum = 3, Value = 0 };
            var presetLbl = new Label { Top = 91, Left = 14, Width = 92, Text = "NR preset" };
            _intensityBox = new NumericUpDown
            {
                Top = 88,
                Left = 300,
                Width = 52,
                Minimum = 1,
                Maximum = 4,
                DecimalPlaces = 1,
                Increment = 0.5m,
                Value = 2
            };
            var intenLbl = new Label { Top = 91, Left = 170, Width = 120, Text = "NR intensity" };
            _feederBox = new ComboBox
            {
                Top = 88,
                Left = 410,
                Width = 112,
                DropDownStyle = ComboBoxStyle.DropDownList,
                Items = { "auto", "forced", "off" }
            };
            _feederBox.SelectedIndex = 0;
            var feederLbl = new Label { Top = 91, Left = 366, Width = 42, Text = "Feeder" };
            _apiBox = new ComboBox
            {
                Top = 88,
                Left = 640,
                Width = 198,
                DropDownStyle = ComboBoxStyle.DropDownList,
                Items = { "auto", "d3d12", "d3d11", "d3d10", "dxgi", "vulkan", "d3d9", "d3d8", "opengl" }
            };
            _apiBox.SelectedIndex = 0;
            var apiLbl = new Label { Top = 91, Left = 550, Width = 88, Text = "Force API" };

            _cleanFry = new CheckBox { Top = 120, Left = 14, Width = 170, Text = "Clean Fry (multi-pass)" };
            _texBoost = new CheckBox { Top = 120, Left = 190, Width = 160, Text = "Texture Boost (8K)" };
            _uplift = new CheckBox { Top = 120, Left = 356, Width = 140, Text = "NeuralUplift (RenoDX)" };
            _dryRun = new CheckBox { Top = 120, Left = 510, Width = 74, Text = "Dry run" };
            _force = new CheckBox { Top = 120, Left = 590, Width = 66, Text = "Force" };
            _launch = new CheckBox { Top = 120, Left = 660, Width = 96, Text = "Launch game" };

            g.Controls.AddRange(new Control[]
            {
                providerLbl, _rbChicken, _rbRenodx, passLbl, _passes, workLbl, _workRes,
                styleLbl, _styleBox, mvLbl, _mvBox, presetLbl, _presetBox, intenLbl, _intensityBox,
                feederLbl, _feederBox, apiLbl, _apiBox,
                _cleanFry, _texBoost, _uplift, _dryRun, _force, _launch
            });
            Controls.Add(g);
        }

        private Button MkButton(string text, Color color)
        {
            var b = new Button
            {
                Text = text,
                Dock = DockStyle.Fill,
                BackColor = color,
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat
            };
            b.FlatAppearance.BorderSize = 0;
            b.Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
            return b;
        }

        private void Log(string line)
        {
            if (InvokeRequired) { BeginInvoke(new Action<string>(Log), line); return; }
            _log.AppendText(line + "\r\n");
            _log.SelectionStart = _log.TextLength;
            _log.ScrollToCaret();
        }

        private void SetBusy(bool busy)
        {
            _installBtn.Enabled = _verifyBtn.Enabled = _uninstallBtn.Enabled = _scanBtn.Enabled = !busy;
            UseWaitCursor = busy;
        }

        private string EntryPoint() { return _scriptPath; }

        private void DoScan()
        {
            var dir = _gameDirBox.Text.Trim().Trim('"');
            if (dir.Length == 0 || !Directory.Exists(dir)) { Log("[error] choose an existing game folder."); return; }
            SetBusy(true);
            _candidates.Clear();
            _gameList.Items.Clear();
            _scanSummary.Text = "Scanning...";

            var t = new Thread(() =>
            {
                var dict = RunPs("-Scan -Json -GamePath \"" + dir + "\"");
                BeginInvoke(new Action(() =>
                {
                    try
                    {
                        SetBusy(false);
                        if (dict == null) { _scanSummary.Text = "Scan failed (see log)."; return; }
                        var cands = dict["candidates"] as ArrayList ?? new ArrayList();
                        foreach (object c in cands)
                        {
                            var d = (Dictionary<string, object>)c;
                            _candidates.Add(d);
                            var name = (d["Name"] ?? "?").ToString();
                            var bits = (d["Bitness"] ?? "?").ToString();
                            var label = (d["Label"] ?? "undetected").ToString();
                            var via = (d["Via"] ?? "").ToString();
                            var it = new ListViewItem(name);
                            it.SubItems.Add(bits);
                            it.SubItems.Add(label);
                            it.SubItems.Add(via);
                            it.Tag = name;
                            _gameList.Items.Add(it);
                        }
                        var ch = dict["chosen"] as Dictionary<string, object>;
                        var resh = dict["reshade"] as Dictionary<string, object>;
                        string chosen = ch != null && ch.ContainsKey("Name") ? ch["Name"].ToString() : "none";
                        bool hasReshade = resh != null && resh.ContainsKey("present");
                        bool rr;
                        if (hasReshade) hasReshade = bool.TryParse(resh["present"].ToString(), out rr) && rr;
                        string reshText = hasReshade
                            ? "ReShade " + resh["file"] + " v" + resh["version"]
                            : "ReShade: none";
                        _scanSummary.Text = "Chosen: " + chosen +
                                            " | native DLSS: " + dict["hasNativeDlss"] +
                                            " | " + reshText +
                                            " | " + _candidates.Count + " executables";
                    }
                    catch (Exception ex) { Log("[error] scan: " + ex.Message); }
                }));
            });
            t.IsBackground = true;
            t.Start();
        }

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
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + EntryPoint() + "\" " + args
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

        private string SelectedExe()
        {
            if (_gameList.SelectedItems.Count > 0)
                return _gameList.SelectedItems[0].Tag == null ? "" : _gameList.SelectedItems[0].Tag.ToString();
            if (_candidates.Count > 0 && _candidates[0].ContainsKey("Name"))
                return _candidates[0]["Name"].ToString();
            return "";
        }

        private string BuildArgs(string action)
        {
            var dir = _gameDirBox.Text.Trim().Trim('"');
            var sb = new StringBuilder("-" + action + " -Json -GamePath \"" + dir + "\"");
            var exe = SelectedExe();
            if (exe.Length > 0) sb.Append(" -Exe \"").Append(exe).Append("\"");
            sb.Append(" -Provider ").Append(_rbChicken.Checked ? "chicken" : "renodx");
            sb.Append(" -Passes ").Append(((int)_passes.Value));
            sb.Append(" -WorkResolution ").Append(((int)_workRes.Value));
            if (_styleBox.SelectedIndex >= 0) sb.Append(" -Style ").Append(_styleBox.SelectedItem);
            sb.Append(" -Preset ").Append(((int)_presetBox.Value));
            sb.Append(" -Intensity ").Append(((double)_intensityBox.Value).ToString(CultureInfo.InvariantCulture));
            if (_mvBox.SelectedIndex >= 0) sb.Append(" -MVProvider ").Append(_mvBox.SelectedIndex);
            if (_feederBox.SelectedIndex > 0) sb.Append(" -Feeder ").Append(_feederBox.SelectedItem);
            if (_apiBox.SelectedIndex > 0) sb.Append(" -Api ").Append(_apiBox.SelectedItem);
            if (_cleanFry.Checked) sb.Append(" -CleanFry");
            if (_texBoost.Checked) sb.Append(" -TextureBoost");
            if (_uplift.Checked) sb.Append(" -NeuralUplift");
            if (_dryRun.Checked) sb.Append(" -DryRun");
            if (_force.Checked) sb.Append(" -Force");
            if (_launch.Checked) sb.Append(" -Launch");
            return sb.ToString();
        }

        private void RunAction(string action)
        {
            var dir = _gameDirBox.Text.Trim().Trim('"');
            if (dir.Length == 0 || !Directory.Exists(dir)) { Log("[error] choose an existing game folder first."); return; }
            if (action != "Uninstall" && _candidates.Count == 0) DoScan();
            SetBusy(true);
            Log(">> " + action + " " + Path.GetFileName(dir) + " ...");

            var t = new Thread(() =>
            {
                Dictionary<string, object> dict = null;
                string runAction = action;
                try { dict = RunPs(BuildArgs(action)); }
                catch (Exception ex)
                {
                    BeginInvoke(new Action(() => Log("[error] " + ex.Message)));
                    BeginInvoke(new Action(() => SetBusy(false)));
                    return;
                }
                BeginInvoke(new Action(() =>
                {
                    try
                    {
                        SetBusy(false);
                        if (dict == null) { Log("== backend produced no result (see errors above)."); return; }
                        if (runAction == "Install")
                        {
                            var files = dict["added"] is ArrayList ? ((ArrayList)dict["added"]).Count : 0;
                            Log("== installed: provider=" + dict["provider"] + " api=" + dict["api"] +
                                " feeder=" + dict["feeder"] + " files=" + files + " dryRun=" + dict["dryRun"]);
                            DoScan();
                        }
                        else if (runAction == "Verify")
                        {
                            var checks = dict["checks"] as ArrayList ?? new ArrayList();
                            foreach (object c in checks)
                            {
                                var d = (Dictionary<string, object>)c;
                                bool ok = false;
                                if (d["Ok"] != null) bool.TryParse(d["Ok"].ToString(), out ok);
                                Log("   [" + (ok ? "OK" : "FAIL") + "] " + d["Item"] + "  " + d["Note"]);
                            }
                        }
                        else
                        {
                            Log("== uninstall: removed=" + ((ArrayList)dict["removed"]).Count +
                                " restored=" + ((ArrayList)dict["restored"]).Count);
                            DoScan();
                        }
                        SetBusy(false);
                    }
                    catch (Exception ex)
                    {
                        Log("[error] " + ex.Message);
                        SetBusy(false);
                    }
                }));
            });
            t.IsBackground = true;
            t.Start();
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