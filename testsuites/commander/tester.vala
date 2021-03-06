/*
 *  This file is part of Netsukuku.
 *  Copyright (C) 2016 Luca Dionisi aka lukisi <luca.dionisi@gmail.com>
 *
 *  Netsukuku is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  Netsukuku is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with Netsukuku.  If not, see <http://www.gnu.org/licenses/>.
 */

using Gee;
using TaskletSystem;

namespace ProofOfConcept
{
    ITasklet tasklet;
    Commander cm;
    class CommanderTester : Object
    {
        public void set_up ()
        {
        }

        public void tear_down ()
        {
        }

        public void test_2()
        {
            cm = Commander.get_singleton();
            cm.stop_console_log();
            cm.single_command(new ArrayList<string>.wrap({"touch", "/tmp/test_commander_2"}));
            cm.single_command(new ArrayList<string>.wrap({"rm", "/tmp/test_commander_2"}));
        }

        public void test_3()
        {
            cm = Commander.get_singleton();
            cm.stop_console_log();
            cm.single_command(new ArrayList<string>.wrap({"touch", "/tmp/test_commander_3"}));
            cm.single_command(new ArrayList<string>.wrap({"rm", "/tmp/test_commander_3"}));
            cm.single_command(new ArrayList<string>.wrap({"touch", "/tmp/test commander 3 new"}));
            cm.single_command(new ArrayList<string>.wrap({"rm", "/tmp/test commander 3 new"}));
        }

        public void test_1()
        {
            cm = Commander.get_singleton();
            // cm.start_console_log();
            Tasklet1 t1 = new Tasklet1();
            Tasklet2 t2 = new Tasklet2();
            Tasklet3 t3 = new Tasklet3();
            tasklet.spawn(t1);
            tasklet.spawn(t2);
            tasklet.spawn(t3);
            tasklet.ms_wait(250);
            // cm.stop_console_log();
        }

        public static int main(string[] args)
        {
            GLib.Test.init(ref args);

            // Initialize tasklet system
            PthTaskletImplementer.init();
            tasklet = PthTaskletImplementer.get_tasklet_system();

            GLib.Test.add_func ("/ProofOfConcept/Commander", () => {
                var x = new CommanderTester();
                x.set_up();
                x.test_1();
                x.test_2();
                x.test_3();
                x.tear_down();
            });
            GLib.Test.run();

            PthTaskletImplementer.kill();
            return 0;
        }
    }

    class Tasklet1 : Object, ITaskletSpawnable
    {
        public void * func()
        {
            int bid = cm.begin_block();
            tasklet.ms_wait(30);
            cm.single_command_in_block(bid, new ArrayList<string>.wrap({"echo", "1"}));
            cm.single_command_in_block(bid, new ArrayList<string>.wrap({"echo", "2"}));
            cm.end_block(bid);
            return null;
        }
    }

    class Tasklet2 : Object, ITaskletSpawnable
    {
        public void * func()
        {
            tasklet.ms_wait(10);
            int bid = cm.begin_block();
            tasklet.ms_wait(20);
            cm.single_command_in_block(bid, new ArrayList<string>.wrap({"echo", "3"}));
            cm.end_block(bid);
            cm.single_command(new ArrayList<string>.wrap({"echo", "5"}));
            return null;
        }
    }

    class Tasklet3 : Object, ITaskletSpawnable
    {
        public void * func()
        {
            tasklet.ms_wait(20);
            cm.single_command(new ArrayList<string>.wrap({"echo", "4"}), false);
            // print("0\n");
            return null;
        }
    }
}
