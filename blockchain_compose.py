#!/usr/bin/env python3

# Helper script to launch containers for testing. Called indirectly by Make
# targets.

from glob import glob
import os
import shlex
import subprocess
import sys


class compose(object):

    DEFAULT_PRE_SCRIPT_DIRS = ['compose/setenv.d', 'compose/local.d']

    def __init__(self):
        self.env = None
        self.pre_script_dirs = [d for d in self.DEFAULT_PRE_SCRIPT_DIRS]

    def main(self):
        import argparse

        arg_parser = argparse.ArgumentParser()
        arg_parser.add_argument('--pre-script-dir',
                                nargs='*',
                                help='scripts to source before running docker-compose')
        arg_parser.add_argument('--sudo', action='store_true')
        arg_parser.add_argument('env')

        subparsers = arg_parser.add_subparsers()
        up_parser = subparsers.add_parser('up')
        up_parser.add_argument('--detached', '-d', action='store_true')
        up_parser.set_defaults(parser_func=self.up)

        down_parser = subparsers.add_parser('down')
        down_parser.set_defaults(parser_func=self.down)

        start_parser = subparsers.add_parser('start')
        start_parser.add_argument('services', nargs='*')
        start_parser.set_defaults(parser_func=self.start)

        stop_parser = subparsers.add_parser('stop')
        stop_parser.add_argument('services', nargs='*')
        stop_parser.set_defaults(parser_func=self.stop)

        create_parser = subparsers.add_parser('create')
        create_parser.add_argument('--force-recreate', action='store_true')
        create_parser.add_argument('--build', action='store_true')
        create_parser.add_argument('--no-build', dest='build', action='store_false')
        create_parser.add_argument('services', nargs='*')
        create_parser.set_defaults(parser_func=self.create)

        logs_parser = subparsers.add_parser('logs')
        logs_parser.add_argument('--follow', '-f', action='store_true')
        logs_parser.add_argument('--tail', '-t')
        logs_parser.add_argument('services', nargs='*')
        logs_parser.set_defaults(parser_func=self.logs)

        args = arg_parser.parse_args()

        self.env = args.env
        if args.pre_script_dir:
            self.pre_script_dirs = args.pre_script_dir

        if 'parser_func' not in vars(args):
            # no environment given
            sys.stderr.write('no sub-command given\n\n')
            arg_parser.print_help()
            exit(1)

        args_ignore = set(['parser_func', 'env', 'pre_script_dir'])
        kwargs = {k: v for k, v in vars(args).items() if k not in args_ignore}
        os.environ['COMPOSE_PROJECT_NAME'] = 'fnb'
        args.parser_func(**kwargs)

    def up(self, sudo=False, detached=False):
        cmd = self._docker_compose_prefix(sudo=sudo)
        cmd.append('up')
        if detached:
            cmd.append('-d')
        cmd_full = self._build_command(cmd)
        self._exec_command(cmd_full)

    def down(self, sudo=False):
        cmd = self._docker_compose_prefix(sudo=sudo)
        cmd.append('down')
        cmd_full = self._build_command(cmd)
        self._exec_command(cmd_full)

    def start(self, services=None, sudo=False):
        cmd = self._docker_compose_prefix(sudo=sudo)
        cmd.append('start')

        if services is not None:
            cmd.extend(services)

        cmd_full = self._build_command(cmd)
        self._exec_command(cmd_full)

    def stop(self, services=None, sudo=False):
        cmd = self._docker_compose_prefix(sudo=sudo)
        cmd.append('stop')

        if services is not None:
            cmd.extend(services)

        cmd_full = self._build_command(cmd)
        self._exec_command(cmd_full)

    def create(self, services=None, build=None, force_recreate=False, sudo=False):
        cmd = self._docker_compose_prefix(sudo=sudo)
        cmd.append('create')
        if force_recreate:
            cmd.append('--force-recreate')

        if build is not None:
            if build:
                cmd.append('--build')
            else:
                cmd.append('--no-build')

        if services is not None:
            cmd.extend(services)

        cmd_full = self._build_command(cmd)
        self._exec_command(cmd_full)

    def logs(self, services=None, sudo=False, follow=False, tail=None):
        cmd = self._docker_compose_prefix(sudo=sudo)
        cmd.append('logs')
        if follow:
            cmd.append('-f')
        if tail:
            cmd.append('--tail={}'.format(tail))
        if services is not None:
            cmd.extend(services)
        cmd_full = self._build_command(cmd)
        self._exec_command(cmd_full)

    def _docker_compose_file(self):
        return os.path.join('compose', self.env+'.yaml')

    def _docker_compose_prefix(self, sudo=False):
        prefix = []
        if sudo:
            prefix.extend(['sudo', '-E'])
        prefix.append('docker-compose')
        prefix.extend(['-f', self._docker_compose_file()])
        return prefix

    def _build_command(self, cmd):
        '''
        The command cmd should include 'docker-compose' and 'sudo' (if required).
        '''
        script = self._build_command_script(cmd)
        return ['bash', '-c', '\n' + script]  # add newline for debug printing purposes

    def _build_command_script(self, cmd):
        script = self._build_pre_script()
        script += ' '.join((shlex.quote(a) for a in cmd))
        script += '\n'
        return script

    def _build_pre_script(self):
        scripts = []
        for d in self.pre_script_dirs:
            if not os.path.isdir(d):
                sys.stderr.write('pre-script: skipping non-directory {}'.format(d))
                continue
            scripts.extend(glob(os.path.join(d, '*.sh')))
        return ''.join(('. {}\n'.format(shlex.quote(s)) for s in scripts))

    def _exec_command(self, cmd, dry_run=False):
        sys.stderr.write('{}\n'.format(' '.join(shlex.quote(a) for a in cmd)))
        if not dry_run:
            subprocess.check_call(cmd, stdout=sys.stdout, stderr=sys.stderr)


if __name__ == '__main__':
    main = compose()
    main.main()
