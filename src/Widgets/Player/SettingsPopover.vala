/*-
 * Copyright 2013-2021 elementary, Inc. (https://elementary.io)
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
 * Authored by: Corentin Noël <corentin@elementaryos.org>
 */

public class Audience.Widgets.SettingsPopover : Gtk.Popover {
    public ClutterGst.Playback playback { get; construct; }
    public bool is_setup = false;

    private Gtk.ComboBoxText languages;
    private Gtk.ComboBoxText subtitles;
    private Gtk.FileChooserButton external_subtitle_file;

    public SettingsPopover (ClutterGst.Playback playback) {
        Object (playback: playback);
    }

    construct {
        languages = new Gtk.ComboBoxText ();
        subtitles = new Gtk.ComboBoxText ();

        var all_files_filter = new Gtk.FileFilter ();
        all_files_filter.set_filter_name (_("All files"));
        all_files_filter.add_pattern ("*");

        var subtitle_files_filter = new Gtk.FileFilter ();
        subtitle_files_filter.set_filter_name (_("Subtitle files"));
        subtitle_files_filter.add_mime_type ("application/smil"); // .smi
        subtitle_files_filter.add_mime_type ("application/x-subrip"); // .srt
        subtitle_files_filter.add_mime_type ("text/x-microdvd"); // .sub
        subtitle_files_filter.add_mime_type ("text/x-ssa"); // .ssa & .ass
        // exclude .asc, mimetype is generic "application/pgp-encrypted"

        external_subtitle_file = new Gtk.FileChooserButton (_("External Subtitles"), Gtk.FileChooserAction.OPEN);
        external_subtitle_file.add_filter (subtitle_files_filter);
        external_subtitle_file.add_filter (all_files_filter);

        var lang_label = new Gtk.Label (_("Audio:")) {
            halign = Gtk.Align.END
        };

        var sub_label = new Gtk.Label (_("Subtitles:")) {
            halign = Gtk.Align.END
        };

        var sub_ext_label = new Gtk.Label (_("External Subtitles:")) {
            halign = Gtk.Align.END
        };

        var setupgrid = new Gtk.Grid () {
            column_spacing = 12,
            row_spacing = 6,
            margin = 6
        };
        setupgrid.attach (lang_label, 0, 1);
        setupgrid.attach (languages, 1, 1);
        setupgrid.attach (sub_label, 0, 2);
        setupgrid.attach (subtitles, 1, 2);
        setupgrid.attach (sub_ext_label, 0, 3);
        setupgrid.attach (external_subtitle_file, 1, 3);
        setupgrid.show_all ();

        external_subtitle_file.file_set.connect (() => {
            ((Audience.Window)((Gtk.Application) Application.get_default ()).active_window).player_page.set_subtitle (external_subtitle_file.get_uri ());
        });

        unowned Gst.Pipeline pipeline = playback.get_pipeline () as Gst.Pipeline;
        /* playback.subtitle_uri does not seem to notify so connect directly to the pipeline */
        pipeline.notify["suburi"].connect (() => {
            /* Easier to retrieve the uri from the playback than the pipeline */
            external_subtitle_file.select_uri (playback.subtitle_uri ?? "");
        });

        subtitles.changed.connect (on_subtitles_changed);

        languages.changed.connect (on_languages_changed);

        add (setupgrid);

        map.connect (() => {
            setup ();
        });
    }

    private void setup () {
        if (!is_setup) {
            is_setup = true;
            setup_text ();
            setup_audio ();
        }
    }

    private void on_subtitles_changed () {
        if (subtitles.active < 0) {
            return;
        }

        if (subtitles.active_id == "none") {
            playback.subtitle_track = -1;
        } else {
            playback.subtitle_track = subtitles.active;
        }
    }

    private void on_languages_changed () {
        if (languages.active < 0 || languages.active_id == "def") {
            return;
        }

        playback.audio_stream = languages.active;
    }

    private void setup_text () {
        subtitles.changed.disconnect (on_subtitles_changed);

        if (subtitles.model.iter_n_children (null) > 0) {
            subtitles.remove_all ();
        }

        uint track = 1;
        playback.get_subtitle_tracks ().foreach ((lang) => {
            // FIXME: Using Track since lang is actually a bad pointer :/
            subtitles.append (lang, _("Track %u").printf (track++));
        });
        subtitles.append ("none", _("None"));

        int count = subtitles.model.iter_n_children (null);
        subtitles.sensitive = count > 1;
        if (subtitles.sensitive && (playback.subtitle_track >= 0)) {
            subtitles.active = playback.subtitle_track;
        } else {
            subtitles.active = count - 1;
        }

        subtitles.changed.connect (on_subtitles_changed);
    }

    private void setup_audio () {
        languages.changed.disconnect (on_languages_changed);

        if (languages.model.iter_n_children (null) > 0) {
            languages.remove_all ();
        }

        var languages_names = get_audio_track_names ();
        uint track = 1;
        playback.get_audio_streams ().foreach ((lang) => {
            var audio_stream_lang = languages_names.nth_data (track - 1);
            if (audio_stream_lang != null) {
                languages.append (lang, audio_stream_lang);
            } else {
                languages.append (lang, _("Track %u").printf (track));
            }
            track++;
        });

        int count = languages.model.iter_n_children (null);
        languages.sensitive = count > 1;
        if (languages.sensitive) {
            languages.active = playback.audio_stream;
        } else {
            if (count != 0) {
                languages.remove_all ();
            }
            languages.append ("def", _("Default"));
            languages.active = 0;
        }

        languages.changed.connect (on_languages_changed);
    }

    public void next_audio () {
        setup ();
        int count = languages.model.iter_n_children (null);
        if (count > 0) {
            languages.active = (languages.active + 1) % count;
        }
    }

    public void next_text () {
        setup ();
        int count = subtitles.model.iter_n_children (null);
        if (count > 0) {
            subtitles.active = (subtitles.active + 1) % count;
        }
    }

    private GLib.List<string?> get_audio_track_names () {
        GLib.List<string?> audio_languages = null;

        var discoverer_info = Audience.get_discoverer_info (playback.uri);
        if (discoverer_info != null) {
            var audio_streams = discoverer_info.get_audio_streams ();

            foreach (var audio_stream in audio_streams) {
                unowned string language_code = ((Gst.PbUtils.DiscovererAudioInfo)(audio_stream)).get_language ();
                if (language_code != null) {
                    var language_name = Gst.Tag.get_language_name (language_code);
                    audio_languages.append (language_name);
                } else {
                    audio_languages.append (null);
                }
            }

            // Both ClutterGst and DiscovererAudioInfo return tracks in opposite order.
            audio_languages.reverse ();
        }

        return audio_languages;
    }
}
