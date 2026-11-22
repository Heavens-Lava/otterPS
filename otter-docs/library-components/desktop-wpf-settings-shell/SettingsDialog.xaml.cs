using System.Windows;

namespace OtterLibrary.Views;

public sealed class AppSettingsModel
{
    public bool CheckUpdatesOnStart { get; set; } = true;
    public bool ConfirmOverwrites { get; set; } = true;
    public string LibraryPath { get; set; } = "~/.otter/library";
}

public partial class SettingsDialog : Window
{
    public AppSettingsModel Settings { get; }

    public SettingsDialog(AppSettingsModel existing)
    {
        InitializeComponent();
        Settings = new AppSettingsModel
        {
            CheckUpdatesOnStart = existing.CheckUpdatesOnStart,
            ConfirmOverwrites = existing.ConfirmOverwrites,
            LibraryPath = existing.LibraryPath
        };
        DataContext = Settings;
    }

    private void OnSaveClick(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
        Close();
    }
}
