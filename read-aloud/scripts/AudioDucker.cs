// Lowers the volume of other applications' audio sessions while Speak-Text.ps1 speaks, then restores it.
// Compiled in memory by Add-Type (Windows PowerShell 5.1 compiles C# 5, so keep the syntax conservative).
// Never throws: every public method returns a count (or -1 for "could not run") and leaves audio alone on any error.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;

public static class AudioDucker
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    private class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams,
            [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionManager2
    {
        [PreserveSig] int GetAudioSessionControl(IntPtr groupingParam, uint streamFlags, out IntPtr sessionControl);
        [PreserveSig] int GetSimpleAudioVolume(IntPtr groupingParam, uint streamFlags, out IntPtr audioVolume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionEnumerator
    {
        [PreserveSig] int GetCount(out int sessionCount);
        [PreserveSig] int GetSession(int sessionCount, out IAudioSessionControl2 session);
    }

    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionControl2
    {
        // IAudioSessionControl (inherited, in vtable order)
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string value, ref Guid eventContext);
        [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string value, ref Guid eventContext);
        [PreserveSig] int GetGroupingParam(out Guid groupingParam);
        [PreserveSig] int SetGroupingParam(ref Guid groupingParam, ref Guid eventContext);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
        // IAudioSessionControl2
        [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetProcessId(out uint processId);
        [PreserveSig] int IsSystemSoundsSession();
        [PreserveSig] int SetDuckingPreference(bool optOut);
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ISimpleAudioVolume
    {
        [PreserveSig] int SetMasterVolume(float level, ref Guid eventContext);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute(bool mute, ref Guid eventContext);
        [PreserveSig] int GetMute(out bool mute);
    }

    private sealed class Session
    {
        public string Id;
        public ISimpleAudioVolume Volume;
    }

    private static List<Session> OpenSessions()
    {
        List<Session> result = new List<Session>();
        IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
        IMMDevice device;
        // dataFlow 0 = render (speakers), role 1 = multimedia
        if (enumerator.GetDefaultAudioEndpoint(0, 1, out device) != 0 || device == null) { return result; }

        Guid managerIid = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
        object managerObj;
        if (device.Activate(ref managerIid, 23, IntPtr.Zero, out managerObj) != 0 || managerObj == null) { return result; }
        IAudioSessionManager2 manager = (IAudioSessionManager2)managerObj;

        IAudioSessionEnumerator sessions;
        if (manager.GetSessionEnumerator(out sessions) != 0 || sessions == null) { return result; }
        int count;
        if (sessions.GetCount(out count) != 0) { return result; }

        int ownPid = Process.GetCurrentProcess().Id;
        for (int i = 0; i < count; i++)
        {
            try
            {
                IAudioSessionControl2 control;
                if (sessions.GetSession(i, out control) != 0 || control == null) { continue; }
                if (control.IsSystemSoundsSession() == 0) { continue; }
                uint pid;
                if (control.GetProcessId(out pid) != 0 || pid == 0 || pid == (uint)ownPid) { continue; }
                string id;
                if (control.GetSessionInstanceIdentifier(out id) != 0 || string.IsNullOrEmpty(id)) { continue; }
                ISimpleAudioVolume volume = control as ISimpleAudioVolume;
                if (volume == null) { continue; }
                Session s = new Session();
                s.Id = id;
                s.Volume = volume;
                result.Add(s);
            }
            catch (Exception) { }
        }
        return result;
    }

    // Lists the sessions that could be ducked, as "id<TAB>volume<TAB>muted" strings (for diagnostics and tests).
    public static string[] ListSessions()
    {
        try
        {
            List<string> lines = new List<string>();
            foreach (Session s in OpenSessions())
            {
                float level; bool muted;
                if (s.Volume.GetMasterVolume(out level) != 0) { continue; }
                if (s.Volume.GetMute(out muted) != 0) { muted = false; }
                lines.Add(s.Id + "\t" + level.ToString("0.00", CultureInfo.InvariantCulture) + "\t" + muted);
            }
            return lines.ToArray();
        }
        catch (Exception) { return new string[0]; }
    }

    // Multiplies every other session's volume by factor (0..1) and records "id<TAB>original<TAB>ducked" in statePath.
    // Muted sessions and sessions already at 0 are left alone. Returns the number of sessions lowered, or -1.
    public static int Duck(double factor, string statePath)
    {
        try
        {
            if (factor < 0.0) { factor = 0.0; }
            if (factor > 1.0) { factor = 1.0; }
            List<string> state = new List<string>();
            Guid none = Guid.Empty;
            foreach (Session s in OpenSessions())
            {
                try
                {
                    float level; bool muted;
                    if (s.Volume.GetMasterVolume(out level) != 0 || level <= 0.0f) { continue; }
                    if (s.Volume.GetMute(out muted) == 0 && muted) { continue; }
                    float lowered = (float)(level * factor);
                    state.Add(s.Id + "\t" + level.ToString("R", CultureInfo.InvariantCulture) + "\t" + lowered.ToString("R", CultureInfo.InvariantCulture));
                }
                catch (Exception) { }
            }
            if (state.Count == 0) { return 0; }
            // Write the state first, so a killed run can be undone by the next one.
            Directory.CreateDirectory(Path.GetDirectoryName(statePath));
            File.WriteAllLines(statePath, state.ToArray());
            int lowerCount = 0;
            foreach (Session s in OpenSessions())
            {
                try
                {
                    foreach (string line in state)
                    {
                        string[] p = line.Split('\t');
                        if (p[0] != s.Id) { continue; }
                        float lowered = float.Parse(p[2], CultureInfo.InvariantCulture);
                        if (s.Volume.SetMasterVolume(lowered, ref none) == 0) { lowerCount++; }
                        break;
                    }
                }
                catch (Exception) { }
            }
            return lowerCount;
        }
        catch (Exception) { return -1; }
    }

    // Puts back the volumes recorded by Duck, but only for sessions still at the volume Duck set
    // (a volume the user changed in the meantime is left alone). Deletes the state file. Returns the number restored, or -1.
    public static int Restore(string statePath)
    {
        try
        {
            if (!File.Exists(statePath)) { return 0; }
            string[] state = File.ReadAllLines(statePath);
            int restored = 0;
            Guid none = Guid.Empty;
            foreach (Session s in OpenSessions())
            {
                try
                {
                    foreach (string line in state)
                    {
                        string[] p = line.Split('\t');
                        if (p.Length != 3 || p[0] != s.Id) { continue; }
                        float original = float.Parse(p[1], CultureInfo.InvariantCulture);
                        float lowered = float.Parse(p[2], CultureInfo.InvariantCulture);
                        float current;
                        if (s.Volume.GetMasterVolume(out current) != 0) { break; }
                        if (Math.Abs(current - lowered) <= 0.02f && s.Volume.SetMasterVolume(original, ref none) == 0) { restored++; }
                        break;
                    }
                }
                catch (Exception) { }
            }
            File.Delete(statePath);
            return restored;
        }
        catch (Exception) { return -1; }
    }
}
