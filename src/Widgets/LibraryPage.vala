// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2016-2016 elementary LLC.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by: Artem Anufrij <artem.anufrij@live.de>
 *
 */

namespace Audience {
    public class LibraryPage : Gtk.ScrolledWindow {

        Gtk.FlowBox view_movies;

        Audience.Services.LibraryManager manager;
        bool poster_initialized = false;

        public LibraryPage () {
        }

        construct {
            view_movies = new Gtk.FlowBox ();
            view_movies.margin = 24;
            view_movies.homogeneous = true;
            view_movies.row_spacing = 12;
            view_movies.column_spacing = 12;
            view_movies.valign = Gtk.Align.START;
            view_movies.selection_mode = Gtk.SelectionMode.NONE;
            view_movies.child_activated.connect ((item) => {
                var selected = (item as Audience.LibraryItem);
                if (selected.video.video_file.query_exists ()) {
                    App.get_instance ().mainwindow.play_file (selected.video.video_file.get_uri ());
                } else {
                    remove_item (selected);
                }
            });

            view_movies.set_sort_func ((child1, child2) => {
                var item1 = child1 as LibraryItem;
                var item2 = child2 as LibraryItem;
                if (item1 != null && item2 != null) {
                        return item1.video.file.collate (item2.video.file);
                    }
                return 0;
            });

            manager = Audience.Services.LibraryManager.get_instance ();
            manager.video_file_detected.connect (add_item);
            manager.begin_scan ();

            this.add (view_movies);

            map.connect (() => {
                if (!poster_initialized) {
                    poster_initialized = true;
                    poster_initialisation.begin ();
                }
            });
        }

        private void add_item (Audience.Objects.Video video) {
            Audience.LibraryItem new_item = new Audience.LibraryItem (video);
            new_item.file_moved.connect (() => {
                remove_item (new_item);
            });
            view_movies.add (new_item);
        }

        private void remove_item (LibraryItem item) {
            manager.clear_cache (item.video);
            item.dispose ();
        }

        private async void poster_initialisation () {
            foreach (var child in view_movies.get_children ()) {
                (child as LibraryItem).video.initialize_poster.begin ();
            }
        }
    }
}
