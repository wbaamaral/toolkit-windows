function Initialize-LsaInterop {
    <#
    .SYNOPSIS
        Garante que o tipo de interop LSA (Wba.Interop.LsaSecretManager) esteja carregado.

    .DESCRIPTION
        Compila, uma unica vez por sessao, o wrapper P/Invoke sobre advapi32 usado para
        armazenar, remover e verificar a presenca de segredos privados da LSA (Local
        Security Authority). E assim que o autologon do Windows guarda a senha
        ('DefaultPassword') sem grava-la em texto claro no registro (conformidade ADR 0005).

        Compativel com .NET Framework 4.x (Windows PowerShell 5.1).
    #>
    [CmdletBinding()]
    param()

    if ('Wba.Interop.LsaSecretManager' -as [type]) {
        return
    }

    $source = @'
using System;
using System.Runtime.InteropServices;

namespace Wba.Interop
{
    public static class LsaSecretManager
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_UNICODE_STRING
        {
            public ushort Length;
            public ushort MaximumLength;
            public IntPtr Buffer;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_OBJECT_ATTRIBUTES
        {
            public int Length;
            public IntPtr RootDirectory;
            public IntPtr ObjectName;
            public uint Attributes;
            public IntPtr SecurityDescriptor;
            public IntPtr SecurityQualityOfService;
        }

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint LsaOpenPolicy(
            IntPtr SystemName,
            ref LSA_OBJECT_ATTRIBUTES ObjectAttributes,
            uint DesiredAccess,
            out IntPtr PolicyHandle);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint LsaStorePrivateData(
            IntPtr PolicyHandle,
            ref LSA_UNICODE_STRING KeyName,
            ref LSA_UNICODE_STRING PrivateData);

        [DllImport("advapi32.dll", SetLastError = true, EntryPoint = "LsaStorePrivateData")]
        private static extern uint LsaStorePrivateDataNull(
            IntPtr PolicyHandle,
            ref LSA_UNICODE_STRING KeyName,
            IntPtr PrivateData);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern uint LsaRetrievePrivateData(
            IntPtr PolicyHandle,
            ref LSA_UNICODE_STRING KeyName,
            out IntPtr PrivateData);

        [DllImport("advapi32.dll")]
        private static extern uint LsaClose(IntPtr PolicyHandle);

        [DllImport("advapi32.dll")]
        private static extern uint LsaFreeMemory(IntPtr Buffer);

        [DllImport("advapi32.dll")]
        private static extern int LsaNtStatusToWinError(uint status);

        private const uint POLICY_CREATE_SECRET = 0x00000020;
        private const uint POLICY_GET_PRIVATE_INFORMATION = 0x00000004;

        private static LSA_UNICODE_STRING InitString(string s)
        {
            LSA_UNICODE_STRING lus = new LSA_UNICODE_STRING();
            if (s == null)
            {
                lus.Buffer = IntPtr.Zero;
                lus.Length = 0;
                lus.MaximumLength = 0;
                return lus;
            }
            lus.Buffer = Marshal.StringToHGlobalUni(s);
            lus.Length = (ushort)(s.Length * 2);
            lus.MaximumLength = (ushort)((s.Length * 2) + 2);
            return lus;
        }

        private static IntPtr OpenPolicy(uint access)
        {
            LSA_OBJECT_ATTRIBUTES attrs = new LSA_OBJECT_ATTRIBUTES();
            attrs.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));
            IntPtr handle;
            uint status = LsaOpenPolicy(IntPtr.Zero, ref attrs, access, out handle);
            if (status != 0)
            {
                throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(status));
            }
            return handle;
        }

        public static void Store(string key, string value)
        {
            IntPtr policy = OpenPolicy(POLICY_CREATE_SECRET);
            LSA_UNICODE_STRING k = InitString(key);
            LSA_UNICODE_STRING v = InitString(value);
            try
            {
                uint status = LsaStorePrivateData(policy, ref k, ref v);
                if (status != 0)
                {
                    throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(status));
                }
            }
            finally
            {
                if (k.Buffer != IntPtr.Zero) Marshal.FreeHGlobal(k.Buffer);
                if (v.Buffer != IntPtr.Zero)
                {
                    for (int i = 0; i < v.Length; i++) Marshal.WriteByte(v.Buffer, i, 0);
                    Marshal.FreeHGlobal(v.Buffer);
                }
                LsaClose(policy);
            }
        }

        public static void Delete(string key)
        {
            IntPtr policy = OpenPolicy(POLICY_CREATE_SECRET);
            LSA_UNICODE_STRING k = InitString(key);
            try
            {
                uint status = LsaStorePrivateDataNull(policy, ref k, IntPtr.Zero);
                if (status != 0)
                {
                    throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(status));
                }
            }
            finally
            {
                if (k.Buffer != IntPtr.Zero) Marshal.FreeHGlobal(k.Buffer);
                LsaClose(policy);
            }
        }

        public static bool Exists(string key)
        {
            IntPtr policy = OpenPolicy(POLICY_GET_PRIVATE_INFORMATION);
            LSA_UNICODE_STRING k = InitString(key);
            IntPtr data = IntPtr.Zero;
            try
            {
                uint status = LsaRetrievePrivateData(policy, ref k, out data);
                if (status != 0 || data == IntPtr.Zero)
                {
                    return false;
                }
                LSA_UNICODE_STRING result = (LSA_UNICODE_STRING)Marshal.PtrToStructure(data, typeof(LSA_UNICODE_STRING));
                return result.Length > 0;
            }
            finally
            {
                if (data != IntPtr.Zero) LsaFreeMemory(data);
                if (k.Buffer != IntPtr.Zero) Marshal.FreeHGlobal(k.Buffer);
                LsaClose(policy);
            }
        }
    }
}
'@

    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}
