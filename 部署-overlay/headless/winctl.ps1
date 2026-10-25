param(
  [string]$Mode = "list",
  [int]$X = 0, [int]$Y = 0
)
$src = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class W {
  public delegate bool CB(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(CB cb, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint data, UIntPtr extra);
  public struct RECT { public int L; public int T; public int R; public int B; }
}
"@
Add-Type -TypeDefinition $src

if ($Mode -eq "list") {
  $items = New-Object System.Collections.ArrayList
  $cb = [W+CB]{
    param($h, $l)
    if ([W]::IsWindowVisible($h)) {
      $len = [W]::GetWindowTextLength($h)
      $sb = New-Object System.Text.StringBuilder ([Math]::Max($len, 1) + 1)
      if ($len -gt 0) { [void][W]::GetWindowText($h, $sb, $sb.Capacity) }
      $r = New-Object W+RECT
      [void][W]::GetWindowRect($h, [ref]$r)
      $w = $r.R - $r.L; $ht = $r.B - $r.T
      if ($w -gt 4 -and $ht -gt 4 -and $r.T -gt -10000) {
        $t = $sb.ToString()
        if ([string]::IsNullOrEmpty($t)) { $t = "(none)" }
        [void]$items.Add("TITLE=" + $t + " | RECT=" + $r.L + "," + $r.T + "," + $w + "x" + $ht)
      }
    }
    return $true
  }
  [void][W]::EnumWindows($cb, [IntPtr]::Zero)
  $items
} elseif ($Mode -eq "click") {
  [void][W]::SetCursorPos($X, $Y)
  Start-Sleep -Milliseconds 200
  [W]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [W]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
  Write-Output ("clicked " + $X + "," + $Y)
}
