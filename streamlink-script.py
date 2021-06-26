#!python
import shutil
import sys
import os.path

basedir = os.path.abspath(os.path.dirname(__file__))
pkgdir = os.path.join(basedir, 'packages')
sys.path.insert(0, pkgdir)
os.environ['PYTHONPATH'] = os.pathsep.join([pkgdir, os.environ.get('PYTHONPATH', '')])

if __name__ == '__main__':
    from streamlink_cli.main import main

    # install the config file, if one is not installed
    if not os.path.exists(os.path.join(basedir, "config")):
        shutil.copyfile(os.path.join(basedir, "config.default"),
                        os.path.join(basedir, "config"))
    main()
