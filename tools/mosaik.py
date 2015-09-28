'''
    The MOSAIK aligner
'''

import logging
import os
import os.path
import subprocess
import tools
import util.file

commit_hash = '5c25216d3522d6a33e53875cd76a6d65001e4e67'
url = 'https://github.com/wanpinglee/MOSAIK/archive/{commit_hash}.zip'

log = logging.getLogger(__name__)


class MosaikTool(tools.Tool):

    def __init__(self):
        if os.uname()[0] == 'Darwin':
            if os.uname()[4].endswith('_64'):
                os.environ['BLD_PLATFORM'] = 'macosx64'
            else:
                os.environ['BLD_PLATFORM'] = 'macosx'
        install_methods = []
        destination_dir = os.path.join(util.file.get_build_path(), 'mosaik-{}'.format(commit_hash))
        install_methods.append(
            DownloadAndBuildMosaik(url.format(commit_hash=commit_hash,
                                              os='source'),
                                   os.path.join(destination_dir, 'bin', 'MosaikAligner'),
                                   destination_dir))
        tools.Tool.__init__(self, install_methods=install_methods)

    def version(self):
        return tool_version

    def get_networkFile(self):
        # this is the directory to return
        dir = os.path.join(util.file.get_build_path(), 'mosaik-{}'.format(commit_hash),
                           'MOSAIK-{}/src'.format(commit_hash), 'networkFile')
        if not os.path.isdir(dir):
            # if it doesn't exist, run just the download-unpack portion of the
            #     source installer
            self.get_install_methods()[-1].download()
        assert os.path.isdir(dir)
        return dir


class DownloadAndBuildMosaik(tools.DownloadPackage):

    def post_download(self):
        mosaikDir = os.path.join(self.destination_dir, 'MOSAIK-{}/src'.format(commit_hash))

        # Now we can make:
        os.system('cd "{}" && make -s'.format(mosaikDir))
