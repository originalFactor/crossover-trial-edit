# CrossOver trial override — user-level shadow of <CX_ROOT>/lib/python/demoutils.py
#
# Installed as:  ~/.local/share/cx-trial-patch/python/demoutils.py
# Activated by:  PYTHONPATH pointing at that directory (see ../install-user.sh)
#
# It loads the genuine CodeWeavers module by absolute path and re-exports every
# public name, then replaces demo_status() so the whole product (GUI menu state,
# cxregister, CheckRegistrationOperation) treats the install as licensed.
import importlib.util as _ilu
import os as _os
import sys as _sys

FAKE_CUSTOMER = 'CrossOver'
FAKE_EXPIRES = '2099/12/31'
FAKE_LICENSE_ID = '000000'


def _cx_root():
    root = _os.environ.get('CX_ROOT')
    if root:
        return root
    try:
        import cxutils as _cu
        root = getattr(_cu, 'CX_ROOT', None)
    except Exception:
        root = None
    return root or '/opt/cxoffice'


_cx_root_dir = _cx_root()
_real_dir = _os.path.join(_cx_root_dir, 'lib', 'python')
if _real_dir not in _sys.path:
    _sys.path.append(_real_dir)
_real_path = _os.path.join(_real_dir, 'demoutils.py')

_spec = _ilu.spec_from_file_location('_cx_real_demoutils', _real_path)
_real = _ilu.module_from_spec(_spec)
_spec.loader.exec_module(_real)

for _k, _v in vars(_real).items():
    if not _k.startswith('__'):
        globals()[_k] = _v


def demo_status(licenseFile, sigFile):
    """Always report a registered, non-demo install with a far-future expiry."""
    return (False, FAKE_CUSTOMER, FAKE_EXPIRES, FAKE_LICENSE_ID, False)
