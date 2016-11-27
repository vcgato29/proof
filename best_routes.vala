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
using Netsukuku;
using Netsukuku.Neighborhood;
using Netsukuku.Identities;
using Netsukuku.Qspn;
using TaskletSystem;

namespace ProofOfConcept
{
    class NeighborData : Object
    {
        public string mac;
        public HCoord h;
    }

    class BestRoute : Object
    {
        public string gw;
        public string dev;
    }

    void update_best_paths_per_identity(IdentityData id, HCoord h)
    {
        QspnManager qspn_mgr = (QspnManager)identity_mgr.get_identity_module(id.nodeid, "qspn");
        if (h.pos >= _gsizes[h.lvl]) return; // ignore virtual destination.
        print(@"Debug: IdentityData #$(id.local_identity_index): update_best_path for h ($(h.lvl), $(h.pos)): started.\n");
        // change the route. place current best path to `h`. if none, then change the path to 'unreachable'.

        // Retrieve all routes towards `h`.
        Gee.List<IQspnNodePath> paths;
        try {
            paths = qspn_mgr.get_paths_to(h);
        } catch (QspnBootstrapInProgressError e) {
            paths = new ArrayList<IQspnNodePath>();
        }

        // Compute Netsukuku address of `h`.
        ArrayList<int> h_addr = new ArrayList<int>();
        h_addr.add_all(id.my_naddr.pos);
        h_addr[h.lvl] = h.pos;
        for (int i = 0; i < h.lvl; i++) h_addr[i] = -1;

        // Compute list of neighbors.
        ArrayList<NeighborData> neighbors = new ArrayList<NeighborData>();
        foreach (IdentityArc ia in id.my_identityarcs) if (ia.qspn_arc != null)
        {
            Arc arc = ((IdmgmtArc)ia.arc).arc;
            IQspnNaddr? _neighbour_naddr = qspn_mgr.get_naddr_for_arc(ia.qspn_arc);
            if (_neighbour_naddr == null) continue;
            Naddr neighbour_naddr = (Naddr)_neighbour_naddr;
            INeighborhoodArc neighborhood_arc = arc.neighborhood_arc;
            NeighborData neighbor = new NeighborData();
            neighbor.mac = neighborhood_arc.neighbour_mac;
            neighbor.h = id.my_naddr.i_qspn_get_coord_by_address(neighbour_naddr);
            neighbors.add(neighbor);
        }

        // Find best routes towards `h` for table 'ntk' and for tables 'ntk_from_<MAC>'
        HashMap<string, BestRoute> best_routes = find_best_route_foreach_table(paths, neighbors);

        // Operations now are based on type of my_naddr:
        // Is this the main ID? Do I have a *real* Netsukuku address?
        int real_up_to = id.my_naddr.get_real_up_to();
        int virtual_up_to = id.my_naddr.get_virtual_up_to();
        if (id.main_id)
        {
            if (real_up_to == levels-1)
            {
                // Compute IP dest addresses and src addresses.
                ArrayList<string> ip_dest_set = new ArrayList<string>();
                ArrayList<string> ip_src_set = new ArrayList<string>();
                // Global.
                ip_dest_set.add(ip_global_gnode(h_addr, h.lvl));
                ip_src_set.add(id.ip_global);
                // Anonymizing.
                ip_dest_set.add(ip_anonymizing_gnode(h_addr, h.lvl));
                ip_src_set.add(id.ip_global);
                // Internals. In this case they are guaranteed to be valid.
                for (int t = h.lvl + 1; t <= levels - 1; t++)
                {
                    ip_dest_set.add(ip_internal_gnode(h_addr, h.lvl, t));
                    ip_src_set.add(id.ip_internal[t-1]);
                }

                for (int i = 0; i < ip_dest_set.size; i++)
                {
                    string d_x = ip_dest_set[i];
                    string n_x = ip_src_set[i];
                    // For packets in egress:
                    if (best_routes.has_key("main"))
                        id.network_stack.change_best_path(d_x,
                                best_routes["main"].dev,
                                best_routes["main"].gw,
                                n_x,
                                null);
                    else id.network_stack.change_best_path(d_x, null, null, null, null);
                    // For packets in forward, received from a known MAC:
                    foreach (NeighborData neighbor in neighbors)
                    {
                        if (best_routes.has_key(neighbor.mac))
                        {
                            id.network_stack.change_best_path(d_x,
                                best_routes[neighbor.mac].dev,
                                best_routes[neighbor.mac].gw,
                                null,
                                neighbor.mac);
                        }
                        else
                        {
                            // set unreachable
                            id.network_stack.change_best_path(d_x, null, null, null, neighbor.mac);
                        }
                    }
                    // For packets in forward, received from a unknown MAC:
                    /* No need because the system uses the same as per packets in egress */
                }
            }
            else
            {
                if (h.lvl <= real_up_to)
                {
                    // Compute IP dest addresses and src addresses.
                    ArrayList<string> ip_dest_set = new ArrayList<string>();
                    ArrayList<string> ip_src_set = new ArrayList<string>();
                    // Internals. In this case they MUST be checked.
                    bool invalid_found = false;
                    for (int t = h.lvl + 1; t <= levels - 1; t++)
                    {
                        for (int n_lvl = h.lvl + 1; n_lvl <= t - 1; n_lvl++)
                        {
                            if (h_addr[n_lvl] >= _gsizes[n_lvl])
                            {
                                invalid_found = true;
                                break;
                            }
                        }
                        if (invalid_found) break; // The higher levels will be invalid too.
                        ip_dest_set.add(ip_internal_gnode(h_addr, h.lvl, t));
                        ip_src_set.add(id.ip_internal[t-1]);
                    }

                    for (int i = 0; i < ip_dest_set.size; i++)
                    {
                        string d_x = ip_dest_set[i];
                        string n_x = ip_src_set[i];
                        // For packets in egress:
                        if (best_routes.has_key("main"))
                            id.network_stack.change_best_path(d_x,
                                    best_routes["main"].dev,
                                    best_routes["main"].gw,
                                    n_x,
                                    null);
                        else id.network_stack.change_best_path(d_x, null, null, null, null);
                        // For packets in forward, received from a known MAC:
                        foreach (NeighborData neighbor in neighbors)
                        {
                            if (best_routes.has_key(neighbor.mac))
                            {
                                id.network_stack.change_best_path(d_x,
                                    best_routes[neighbor.mac].dev,
                                    best_routes[neighbor.mac].gw,
                                    null,
                                    neighbor.mac);
                            }
                            else
                            {
                                // set unreachable
                                id.network_stack.change_best_path(d_x, null, null, null, neighbor.mac);
                            }
                        }
                        // For packets in forward, received from a unknown MAC:
                        /* No need because the system uses the same as per packets in egress */
                    }
                }
                else if (h.lvl < virtual_up_to)
                {
                    // Compute IP dest addresses (in this case no src addresses).
                    ArrayList<string> ip_dest_set = new ArrayList<string>();
                    // Internals. In this case they MUST be checked.
                    bool invalid_found = false;
                    for (int t = h.lvl + 1; t <= levels - 1; t++)
                    {
                        for (int n_lvl = h.lvl + 1; n_lvl <= t - 1; n_lvl++)
                        {
                            if (h_addr[n_lvl] >= _gsizes[n_lvl])
                            {
                                invalid_found = true;
                                break;
                            }
                        }
                        if (invalid_found) break; // The higher levels will be invalid too.
                        ip_dest_set.add(ip_internal_gnode(h_addr, h.lvl, t));
                    }

                    for (int i = 0; i < ip_dest_set.size; i++)
                    {
                        string d_x = ip_dest_set[i];

                        // For packets in egress:
                        /* Nothing: We are the main identity, but we don't have a valid src IP at this level. */
                        // For packets in forward, received from a known MAC:
                        foreach (NeighborData neighbor in neighbors)
                        {
                            if (best_routes.has_key(neighbor.mac))
                            {
                                id.network_stack.change_best_path(d_x,
                                    best_routes[neighbor.mac].dev,
                                    best_routes[neighbor.mac].gw,
                                    null,
                                    neighbor.mac);
                            }
                            else
                            {
                                // set unreachable
                                id.network_stack.change_best_path(d_x, null, null, null, neighbor.mac);
                            }
                        }
                        // For packets in forward, received from a unknown MAC:
                        if (best_routes.has_key("main"))
                            id.network_stack.change_best_path(d_x,
                                    best_routes["main"].dev,
                                    best_routes["main"].gw,
                                    null,
                                    null);
                        else id.network_stack.change_best_path(d_x, null, null, null, null);
                    }
                }
                else
                {
                    // Compute IP dest addresses (in this case no src addresses).
                    ArrayList<string> ip_dest_set = new ArrayList<string>();
                    // Global.
                    ip_dest_set.add(ip_global_gnode(h_addr, h.lvl));
                    // Anonymizing.
                    ip_dest_set.add(ip_anonymizing_gnode(h_addr, h.lvl));
                    // Internals. In this case they are guaranteed to be valid.
                    for (int t = h.lvl + 1; t <= levels - 1; t++)
                    {
                        ip_dest_set.add(ip_internal_gnode(h_addr, h.lvl, t));
                    }

                    for (int i = 0; i < ip_dest_set.size; i++)
                    {
                        string d_x = ip_dest_set[i];

                        // For packets in egress:
                        /* Nothing: We are the main identity, but we don't have a valid src IP at this level. */
                        // For packets in forward, received from a known MAC:
                        foreach (NeighborData neighbor in neighbors)
                        {
                            if (best_routes.has_key(neighbor.mac))
                            {
                                id.network_stack.change_best_path(d_x,
                                    best_routes[neighbor.mac].dev,
                                    best_routes[neighbor.mac].gw,
                                    null,
                                    neighbor.mac);
                            }
                            else
                            {
                                // set unreachable
                                id.network_stack.change_best_path(d_x, null, null, null, neighbor.mac);
                            }
                        }
                        // For packets in forward, received from a unknown MAC:
                        if (best_routes.has_key("main"))
                            id.network_stack.change_best_path(d_x,
                                    best_routes["main"].dev,
                                    best_routes["main"].gw,
                                    null,
                                    null);
                        else id.network_stack.change_best_path(d_x, null, null, null, null);
                    }
                }
            }
        }
        else
        {
            if (h.lvl < virtual_up_to)
            {
                // Compute IP dest addresses (in this case no src addresses).
                ArrayList<string> ip_dest_set = new ArrayList<string>();
                // Internals. In this case they MUST be checked.
                bool invalid_found = false;
                for (int t = h.lvl + 1; t <= levels - 1; t++)
                {
                    for (int n_lvl = h.lvl + 1; n_lvl <= t - 1; n_lvl++)
                    {
                        if (h_addr[n_lvl] >= _gsizes[n_lvl])
                        {
                            invalid_found = true;
                            break;
                        }
                    }
                    if (invalid_found) break; // The higher levels will be invalid too.
                    ip_dest_set.add(ip_internal_gnode(h_addr, h.lvl, t));
                }

                for (int i = 0; i < ip_dest_set.size; i++)
                {
                    string d_x = ip_dest_set[i];

                    // For packets in egress:
                    /* Nothing: We are the not main identity. */
                    // For packets in forward, received from a known MAC:
                    foreach (NeighborData neighbor in neighbors)
                    {
                        if (best_routes.has_key(neighbor.mac))
                        {
                            id.network_stack.change_best_path(d_x,
                                best_routes[neighbor.mac].dev,
                                best_routes[neighbor.mac].gw,
                                null,
                                neighbor.mac);
                        }
                        else
                        {
                            // set unreachable
                            id.network_stack.change_best_path(d_x, null, null, null, neighbor.mac);
                        }
                    }
                    // For packets in forward, received from a unknown MAC:
                    if (best_routes.has_key("main"))
                        id.network_stack.change_best_path(d_x,
                                best_routes["main"].dev,
                                best_routes["main"].gw,
                                null,
                                null);
                    else id.network_stack.change_best_path(d_x, null, null, null, null);
                }
            }
            else
            {
                // Compute IP dest addresses (in this case no src addresses).
                ArrayList<string> ip_dest_set = new ArrayList<string>();
                // Global.
                ip_dest_set.add(ip_global_gnode(h_addr, h.lvl));
                // Anonymizing.
                ip_dest_set.add(ip_anonymizing_gnode(h_addr, h.lvl));
                // Internals. In this case they are guaranteed to be valid.
                for (int t = h.lvl + 1; t <= levels - 1; t++)
                {
                    ip_dest_set.add(ip_internal_gnode(h_addr, h.lvl, t));
                }

                for (int i = 0; i < ip_dest_set.size; i++)
                {
                    string d_x = ip_dest_set[i];

                    // For packets in egress:
                    /* Nothing: We are the not main identity. */
                    // For packets in forward, received from a known MAC:
                    foreach (NeighborData neighbor in neighbors)
                    {
                        if (best_routes.has_key(neighbor.mac))
                        {
                            id.network_stack.change_best_path(d_x,
                                best_routes[neighbor.mac].dev,
                                best_routes[neighbor.mac].gw,
                                null,
                                neighbor.mac);
                        }
                        else
                        {
                            // set unreachable
                            id.network_stack.change_best_path(d_x, null, null, null, neighbor.mac);
                        }
                    }
                    // For packets in forward, received from a unknown MAC:
                    if (best_routes.has_key("main"))
                        id.network_stack.change_best_path(d_x,
                                best_routes["main"].dev,
                                best_routes["main"].gw,
                                null,
                                null);
                    else id.network_stack.change_best_path(d_x, null, null, null, null);
                }
            }
        }
    }

    HashMap<string, BestRoute>
    find_best_route_foreach_table(
        Gee.List<IQspnNodePath> paths,
        ArrayList<NeighborData> neighbors)
    {
        HashMap<string, BestRoute> best_routes = new HashMap<string, BestRoute>();
        foreach (IQspnNodePath path in paths)
        {
            QspnArc path_arc = (QspnArc)path.i_qspn_get_arc();
            string path_dev = path_arc.arc.neighborhood_arc.nic.dev;
            string gw = path_arc.arc.neighborhood_arc.neighbour_nic_addr;
            if (best_routes.is_empty)
            {
                string k = "main";
                // absolute best.
                BestRoute r = new BestRoute();
                r.gw = gw;
                r.dev = path_dev;
                best_routes[k] = r;
            }
            bool completed = true;
            foreach (NeighborData neighbor in neighbors)
            {
                // is it best without neighbor?
                string k = neighbor.mac;
                // best_routes contains k?
                if (best_routes.has_key(k)) continue;
                // path contains neighbor's g-node?
                ArrayList<HCoord> searchable_path = new ArrayList<HCoord>((a, b) => a.equals(b));
                foreach (IQspnHop path_h in path.i_qspn_get_hops())
                    searchable_path.add(path_h.i_qspn_get_hcoord());
                if (neighbor.h in searchable_path)
                {
                    completed = false;
                    continue;
                }
                // best without neighbor.
                BestRoute r = new BestRoute();
                r.gw = gw;
                r.dev = path_dev;
                best_routes[k] = r;
            }
            if (completed) break;
        }
        return best_routes;
    }
}