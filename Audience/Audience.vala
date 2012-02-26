
[DBus (name = "org.gnome.SettingsDaemon.MediaKeys")]
public interface GnomeMediaKeys : GLib.Object {
    public abstract void GrabMediaPlayerKeys (string application, uint32 time) throws GLib.IOError;
    public abstract void ReleaseMediaPlayerKeys (string application) throws GLib.IOError;
    public signal void MediaPlayerKeyPressed (string application, string key);
}


namespace Audience{
    
    public const string [] video = {
    "mpg",
    "flv",
    "mp4",
    "avi"
    };
    public const string [] audio = {
    "mp3",
    "ogg"
    };
    
    public static string get_title (string filename){
        var title = get_basename (filename);
        title = title.replace ("%20", " ").
            replace ("%5B", "[").replace ("%5D", "]").replace ("%7B", "{").
            replace ("%7D", "}").replace ("_", " ").replace ("."," ").replace ("  "," ");
        return title;
    }
    
    public static string get_extension (string filename){
        int i=0;
        for (i=filename.length;i!=0;i--){
            if (filename [i] == '.')
                break;
        }
        return filename.substring (i+1);
    }
    public static string get_basename (string filename){
        int i=0;
        for (i=filename.length;i!=0;i--){
            if (filename [i] == '.')
                break;
        }
        int j=0;
        for (j=filename.length;j!=0;j--){
            if (filename[j] == '/')
                break;
        }
        return filename.substring (j + 1, i - j - 1);
    }
    
    public static string seconds_to_time (int secs){
        int hours = 0;
        int min = 0;
        while (secs >= 60){
            ++min;
            secs -= 60;
        }
        int min_tmp = min;
        while (min >= 60){
            ++hours;
            min_tmp -= 60;
        }
        string seconds = (secs < 10)?"0"+secs.to_string ():secs.to_string ();
        
        string ret = (hours > 0)?hours.to_string ():"";
        ret += min.to_string () + ":" + seconds;
        return ret;
    }
    
    class LLabel : Gtk.Label{
        public LLabel (string label){
            this.set_halign (Gtk.Align.START);
            this.label = label;
        }
        public LLabel.indent (string label){
            this (label);
            this.margin_left = 10;
        }
        public LLabel.markup (string label){
            this (label);
            this.use_markup = true;
        }
        public LLabel.right (string label){
            this.set_halign (Gtk.Align.END);
            this.label = label;
        }
        public LLabel.right_with_markup (string label){
            this.set_halign (Gtk.Align.END);
            this.use_markup = true;
            this.label = label;
        }
    }
    
    public class AudienceSettings : Granite.Services.Settings {
        
        public bool move_window          {get; set;}
        public bool keep_aspect          {get; set;}
        public bool show_details         {get; set;}
        public bool resume_videos        {get; set;}
        public string last_played_videos {get; set;} /*video1,time,video2,time2*/
        public string last_folder        {get; set;}
        
        public AudienceSettings (){
            base ("org.elementary.Audience");
        }
        
    }
    
    public class AudienceApp : Granite.Application{
        
        construct{
            program_name = "Audience";
            exec_name = "audience";
            
            build_data_dir = Constants.DATADIR;
            build_pkg_data_dir = Constants.PKGDATADIR;
            build_release_name = Constants.RELEASE_NAME;
            build_version = Constants.VERSION;
            build_version_info = Constants.VERSION_INFO;
            
            app_years = "2011-2012";
            app_icon = "audience";
            app_launcher = "audience.desktop";
            application_id = "net.launchpad.audience";
            
            main_url = "https://code.launchpad.net/audience";
            bug_url = "https://bugs.launchpad.net/audience";
            help_url = "https://code.launchpad.net/audience";
            translate_url = "https://translations.launchpad.net/audience";
            
            /*about_authors = {""};
            about_documenters = {""};
            about_artists = {""};
            about_translators = "Launchpad Translators";
            about_comments = "To be determined"; */
            about_license_type = Gtk.License.GPL_3_0;
        }
        
        public ClutterGst.VideoTexture    canvas;
        public Gtk.Window                 mainwindow;
        public Audience.Widgets.TagView   tagview;
        public Gtk.Scale                  slider;
        public Audience.Widgets.Previewer previewer;
        public GtkClutter.Actor           bar;
        public Gtk.Toolbar                toolbar;
        public Gtk.ToolButton             play;
        public Gtk.ToolButton             pause;
        public Gtk.ToolButton             unfullscreen;
        public Clutter.Stage              stage;
        public bool                       fullscreened;
        public uint                       hiding_timer;
        public GnomeMediaKeys             mediakeys;
        public AudienceSettings           settings;
        public Audience.Widgets.Playlist  playlist;
        public GtkClutter.Embed           clutter;
        public Granite.Widgets.Welcome    welcome;
        
        private float video_w;
        private float video_h;
        private bool  reached_end;
        private bool  error;
        
        private Gdk.Cursor normal_cursor;
        private Gdk.Cursor blank_cursor;
        
        public bool         playing;
        public File         current_file;
        public List<string> last_played_videos; //taken from settings, but splitted
        
        private inline Gtk.Image? sym (string name, string fallback){
            try{
                var icon = Gtk.IconTheme.get_default ().lookup_icon 
                    (name, 24, 0);
                if (icon == null)
                    return new Gtk.Image.from_stock (fallback, Gtk.IconSize.BUTTON);
                return new Gtk.Image.from_pixbuf (icon.load_symbolic
                    ({1.0,1.0,1.0,1.0}, null, null, null, null));
            }catch (Error e){
                warning (e.message);
            }
            return new Gtk.Image.from_stock (Gtk.Stock.MISSING_IMAGE, Gtk.IconSize.BUTTON);
        }
        
        public AudienceApp (){
            Granite.Services.Logger.DisplayLevel = Granite.Services.LogLevel.DEBUG;
            
            Gtk.Settings.get_default ().gtk_application_prefer_dark_theme = true;
            this.flags |= GLib.ApplicationFlags.HANDLES_OPEN;
            
            this.fullscreened = false;
            
            this.playlist   = new Audience.Widgets.Playlist ();
            this.settings   = new AudienceSettings ();
            this.canvas     = new ClutterGst.VideoTexture ();
            this.mainwindow = new Gtk.Window ();
            this.tagview    = new Audience.Widgets.TagView (this);
            this.previewer  = new Audience.Widgets.Previewer ();
            this.bar        = new GtkClutter.Actor ();
            this.toolbar    = new Gtk.Toolbar ();
            var mainbox     = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            this.clutter     = new GtkClutter.Embed ();
            this.stage      = (Clutter.Stage)clutter.get_stage ();
            this.play       = new Gtk.ToolButton (sym ("media-playback-start-symbolic", Gtk.Stock.MEDIA_PLAY), "");
            this.pause      = new Gtk.ToolButton (sym ("media-playback-pause-symbolic", Gtk.Stock.MEDIA_PAUSE), "");
            var time_item   = new Gtk.ToolItem ();
            var slider_item = new Gtk.ToolItem ();
            var remain_item = new Gtk.ToolItem ();
            var volm        = new Gtk.ToolItem ();
            var info        = new Gtk.ToggleToolButton ();
            var open        = new Gtk.ToolButton (sym ("list-add-symbolic", Gtk.Stock.OPEN),"");
            /*var menu        = new Gtk.Menu ();
             The AppMenu is disabled until it contains something useful
            var appm        = this.create_appmenu (menu); */
            this.slider     = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 1);
            var volume      = new Gtk.VolumeButton ();
            var time        = new Gtk.Label ("0");
            var remaining   = new Gtk.Label ("0");
            this.unfullscreen = new Gtk.ToolButton (sym ("view-restore-symbolic", Gtk.Stock.LEAVE_FULLSCREEN), "");
            this.blank_cursor  = new Gdk.Cursor (Gdk.CursorType.BLANK_CURSOR);
            
            //prepare last played videos
            this.last_played_videos = new List<string> ();
            var split = this.settings.last_played_videos.split (",");;
            for (var i=0;i<split.length;i++){
                this.last_played_videos.append (split[i]);
            }
            
            
            this.welcome = new Granite.Widgets.Welcome ("Audience", _("Watching films has never been better"));
            welcome.append ("document-open", _("Open a file"), _("Get file from your disk"));
            welcome.append ("media-cdrom", _("Watch a DVD"), _("Open a film"));
            welcome.append ("internet-web-browser", _("Open a location"), _("Watch something from the infinity of the internet"));
            
            /*UI*/
            this.canvas.reactive = true;
            this.canvas.width    = 624;
            this.canvas.height   = 352;
            
            stage.add_actor (canvas);
            stage.add_actor (tagview);
            stage.add_actor (previewer);
            stage.add_actor (bar);
            stage.color = Clutter.Color.from_string ("#000");
            
            this.tagview.x      = stage.width;
            this.tagview.width  = 350;
            
            slider_item.set_expand (true);
            slider_item.add (slider);
            slider.draw_value = false;
            
            volm.add (volume);
            volume.use_symbolic = true;
            
            time_item.add (time);
            remain_item.add (remaining);
            
            info.icon_widget = sym ("go-previous-symbolic", Gtk.Stock.JUSTIFY_LEFT);
            /* The AppMenu is disabled until it contains something useful
            appm.icon_widget = sym ("document-properties-symbolic"); */
            
            play.sensitive = false;
            
            play.tooltip_text = _("Play");
            pause.tooltip_text = _("Pause");
            time_item.tooltip_text = _("Time In");
            slider_item.tooltip_text = _("Progress");
            remain_item.tooltip_text = _("Time Remaining");
            open.tooltip_text = _("Open");
            info.tooltip_text = _("Sidebar");
            unfullscreen.tooltip_text = _("Leave Fullscreen");
            
            play.margin = time_item.margin = slider_item.margin = pause.margin = 
            volm.margin = info.margin = open.margin /* The AppMenu is disabled until it contains something useful = appm.margin */ = 5;
            
            toolbar.insert (play, -1);
            toolbar.insert (volm, -1);
            toolbar.insert (time_item,   -1);
            toolbar.insert (slider_item, -1);
            toolbar.insert (remain_item, -1);
            toolbar.insert (open, -1);
            /* The AppMenu is disabled until it contains something useful
            toolbar.insert (appm, -1); */
            toolbar.insert (info, -1);
            
            var css = new Gtk.CssProvider ();
            try{
            css.load_from_data ("
                *{
                    background-color:rgba(0,0,0,0);
                    background-image:none;
                    color:white;
                }
                ", -1);
            }catch (Error e){warning (e.message);}
            toolbar.get_style_context ().add_provider (css, 12000);
            remaining.get_style_context ().add_provider (css, 12000);
            time.get_style_context ().add_provider (css, 12000);
            
            bar.get_widget ().draw.connect ( (ctx) => {
                ctx.set_operator (Cairo.Operator.SOURCE);
                ctx.rectangle (0, 0, bar.get_widget ().get_allocated_width  (), 
                                     bar.get_widget ().get_allocated_height ());
                ctx.set_source_rgba (0.0, 0.0, 0.0, 0.8);
                ctx.fill ();
                return false;
            });
            
            toolbar.show_all ();
            ((Gtk.Container)bar.get_widget ()).add (toolbar);
            
            mainbox.pack_start (welcome);
            mainbox.pack_start (clutter);
            
            this.mainwindow.title = program_name;
            this.mainwindow.set_application (this);
            this.mainwindow.add (mainbox);
            this.mainwindow.set_default_size (624, 352);
            this.mainwindow.show_all ();
            
            clutter.hide ();
            
            /*events*/
            playlist.play.connect ( (file) => {
                this.open_file (file.get_path ());
            });
            
            //handle welcome
            welcome.activated.connect ( (index) => {
                if (index == 0){
                    run_open (0);
                }else if (index == 1){
                    run_open (2);
                }else{
                    var d = new Gtk.Dialog.with_buttons (_("Open location"), 
                        this.mainwindow, Gtk.DialogFlags.MODAL, 
                        Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                        Gtk.Stock.OK,     Gtk.ResponseType.OK);
                    var grid  = new Gtk.Grid ();
                    var entry = new Gtk.Entry ();
                    
                    grid.attach (new Gtk.Image.from_icon_name ("internet-web-browser",
                        Gtk.IconSize.DIALOG), 0, 0, 1, 2);
                    grid.attach (new Gtk.Label (_("Choose location")), 1, 0, 1, 1);
                    grid.attach (entry, 1, 1, 1, 1);
                    
                    ((Gtk.Container)d.get_content_area ()).add (grid);
                    grid.show_all ();
                    
                    if (d.run () == Gtk.ResponseType.OK){
                        open_file (entry.text);
                        canvas.get_pipeline ().set_state (Gst.State.PLAYING);
                        welcome.hide ();
                        clutter.show_all ();
                    }
                    d.destroy ();
                }
            });
            
            //check for errors on pipe's bus
            this.canvas.error.connect ( () => {
                warning ("An error occured!\n");
                this.error = true;
            });
            this.canvas.get_pipeline ().get_bus ().add_signal_watch ();
            this.canvas.get_pipeline ().get_bus ().message.connect ( () => {
                var msg = this.canvas.get_pipeline ().get_bus ().peek ();
                if (msg == null)
                    return;
                switch (msg.type){
                    case Gst.MessageType.ERROR:
                        GLib.Error e;
                        string detail;
                        msg.parse_error (out e, out detail);
                        warning (e.message);
                        debug (detail+"\n");
                        this.canvas.get_pipeline ().set_state (Gst.State.NULL);
                        break;
                    case Gst.MessageType.ELEMENT:
                        if (msg.get_structure () != null && 
                            Gst.is_missing_plugin_message (msg)){
                            this.canvas.get_pipeline ().set_state (Gst.State.NULL);
                            debug ("Missing plugin\n");
                            this.error = true;
                            var detail = Gst.missing_plugin_message_get_description (msg);
                            var err = new Gtk.InfoBar.with_buttons (
                                "Do nothing", 0,
                                "Install missing plugins", 1);
                            ((Gtk.Container)err.get_content_area ()).add (new Gtk.Label (
                                "There's something missing to play this file! What now? ("+detail+")"));
                            err.message_type = Gtk.MessageType.ERROR;
                            mainbox.pack_start (err, false);
                            mainbox.reorder_child (err, 0);
                            err.show_all ();
                            
                            err.response.connect ( (id) => {
                                if (id == 1){
                                    var installer = Gst.missing_plugin_message_get_installer_detail
                                       (msg);
                                var context = new Gst.InstallPluginsContext ();
                                    Gst.install_plugins_async ({installer}, context,
                                    () => { //finished
                                        debug ("Finished plugin install\n");
                                        Gst.update_registry ();
                                        mainbox.remove (err);
                                        this.canvas.get_pipeline ().set_state (Gst.State.PLAYING);
                                    });
                                }else{
                                    mainbox.remove (err);
                                }
                            });
                        }
                        break;
                    default:
                        break;
                }
            });
            
            //media keys
            try {
                this.mediakeys = Bus.get_proxy_sync (BusType.SESSION, 
                    "org.gnome.SettingsDaemon", "/org/gnome/SettingsDaemon/MediaKeys");
                this.mediakeys.MediaPlayerKeyPressed.connect ( (bus, app, key) => {
                    if (app != "audience")
                       return;
                    switch (key){
                        case "Previous":
                            this.playlist.previous ();
                            break;
                        case "Next":
                            this.playlist.next ();
                            break;
                        case "Play":
                            this.toggle_play (!this.playing);
                            break;
                        default:
                            break;
                    }
                });
                this.mediakeys.GrabMediaPlayerKeys("audience", (uint32)0);
            } catch (Error e) {
                warning (e.message);
            }
            
            //shortcuts
            this.mainwindow.key_press_event.connect ( (e) => {
                switch (e.keyval){
                    case Gdk.Key.space:
                        this.toggle_play (!this.playing);
                        break;
                    case Gdk.Key.Escape:
                        if (this.fullscreened)
                            this.toggle_fullscreen ();
                        else
                            this.mainwindow.destroy ();
                        break;
                    case Gdk.Key.o:
                        this.run_open (0);
                        break;
                    case Gdk.Key.f:
                    case Gdk.Key.F11:
                        this.toggle_fullscreen ();
                        break;
                    case Gdk.Key.q:
                        this.mainwindow.destroy ();
                        break;
                    case Gdk.Key.Left:
                        if ((this.canvas.progress - 0.05) < 0)
                            this.canvas.progress = 0.0;
                        else
                            this.canvas.progress -= 0.05;
                        break;
                    case Gdk.Key.Right:
                        this.canvas.progress += 0.05;
                        break;
                    default:
                        break;
                }
                return true;
            });
            
            //end
            this.canvas.eos.connect ( () => {
                this.reached_end = true;
                this.toggle_play (false);
                this.playlist.next ();
            });
            
            //slider
            ulong id = slider.value_changed.connect ( () => {
                canvas.progress = slider.get_value () / canvas.duration;
            });
            canvas.notify["progress"].connect ( () => {
                SignalHandler.block (slider, id);
                slider.set_range (0, canvas.duration);
                slider.set_value (canvas.duration * canvas.progress);
                SignalHandler.unblock (slider, id);
                
                time.label = seconds_to_time ((int)slider.get_value ());
                
                remaining.label = "-" + seconds_to_time ((int)(canvas.duration - 
                    slider.get_value ()));
            });
            
            //volume
            volume.value_changed.connect ( () => {
                canvas.audio_volume = volume.value;
            });
            volume.value = 1.0;
            
            //preview thing
            slider.motion_notify_event.connect ( (e) => {
                previewer.x = (float)e.x;
                previewer.y = stage.height - 180;
                Timeout.add (200, () => {
                    previewer.progress = e.x / slider.get_allocated_width ();
                    return false;
                });
                return false;
            });
            slider.enter_notify_event.connect ( (e) => {
                previewer.get_pipeline ().set_state (Gst.State.PLAYING);
                var o2 = 255;
                previewer.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 400, opacity:o2);
                previewer.raise_top ();
                return false;
            });
            slider.leave_notify_event.connect ( (e) => {
                var o2 = 0;
                previewer.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 400, opacity:o2);
                previewer.get_pipeline ().set_state (Gst.State.PAUSED);
                Timeout.add (400, () => {previewer.lower_bottom ();return false;});
                return false;
            });
            
            /*slide controls back in*/
            this.mainwindow.motion_notify_event.connect ( () => {
                float y2 = this.stage.height - 56;
                this.bar.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 100, y:y2);
                this.mainwindow.get_window ().set_cursor (normal_cursor);
                Gst.State state;
                canvas.get_pipeline ().get_state (out state, null, 0);
                if (state == Gst.State.PLAYING){
                    Source.remove (this.hiding_timer);
                    this.hiding_timer = GLib.Timeout.add (2000, () => {
                        this.mainwindow.get_window ().set_cursor (blank_cursor);
                        float y3 = this.stage.height;
                        this.bar.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 1000, y:y3);
                        return false;
                    });
                }
                return false;
            });
            
            /*open location popover*/
            open.clicked.connect ( () => {
                var pop = new Granite.Widgets.PopOver ();
                var box = new Gtk.Grid ();
                ((Gtk.Box)pop.get_content_area ()).add (box);
                
                box.row_spacing    = 5;
                box.column_spacing = 12;
                
                var fil   = new Gtk.Button.with_label (_("File"));
                var fil_i = new Gtk.Image.from_stock (Gtk.Stock.OPEN, Gtk.IconSize.DND);
                var cd    = new Gtk.Button.with_label ("CD");
                var cd_i  = new Gtk.Image.from_icon_name ("media-cdrom-audio", Gtk.IconSize.DND);
                var dvd   = new Gtk.Button.with_label ("DVD");
                var dvd_i = new Gtk.Image.from_icon_name ("media-cdrom", Gtk.IconSize.DND);
                var net   = new Gtk.Button.with_label (_("Network File"));
                var net_i = new Gtk.Image.from_icon_name ("internet-web-browser", Gtk.IconSize.DND);
                
                fil.clicked.connect ( () => {
                    pop.destroy ();
                    run_open (0);
                });
                cd.clicked.connect ( () => {
                    run_open (1);
                    pop.destroy ();
                });
                dvd.clicked.connect ( () => {
                    run_open (2);
                    pop.destroy ();
                });
                net.clicked.connect ( () => {
                    var entry = new Gtk.Entry ();
                    entry.secondary_icon_stock = Gtk.Stock.OPEN;
                    entry.icon_release.connect ( (pos, e) => {
                        open_file (entry.text);
                        canvas.get_pipeline ().set_state (Gst.State.PLAYING);
                        pop.destroy ();
                    });
                    box.remove (net);
                    box.attach (entry, 1, 3, 1, 1);
                    entry.show ();
                });
                
                box.attach (fil_i, 0, 0, 1, 1);
                box.attach (fil,   1, 0, 1, 1);
                box.attach (dvd_i, 0, 1, 1, 1);
                box.attach (dvd,   1, 1, 1, 1);
                box.attach (cd_i,  0, 2, 1, 1);
                box.attach (cd,    1, 2, 1, 1);
                box.attach (net_i, 0, 3, 1, 1);
                box.attach (net,   1, 3, 1, 1);
                
                pop.move_to_widget (open);
                pop.show_all ();
                pop.present ();
                pop.run ();
                pop.destroy ();
            });
            
            play.clicked.connect  ( () => {toggle_play (true);});
            pause.clicked.connect ( () => {toggle_play (false);});
            
            unfullscreen.clicked.connect (toggle_fullscreen);
            
            info.toggled.connect ( () => {
                if (info.active)
                    tagview.expand ();
                else
                    tagview.collapse ();
            });
            
            //fullscreen on maximize
            this.mainwindow.window_state_event.connect ( (e) => {
                if (!((e.window.get_state () & Gdk.WindowState.MAXIMIZED) == 0) && !this.fullscreened){
                    this.mainwindow.fullscreen ();
                    this.fullscreened = true;
                    toolbar.insert (unfullscreen, 4);
                    unfullscreen.show_all ();
                    return true;
                }
                return false;
            });
            
            //positioning
            int old_h=0, old_w=0;
            this.mainwindow.size_allocate.connect ( () => {
                if (this.mainwindow.get_allocated_width () != old_w || 
                    this.mainwindow.get_allocated_height () != old_h){
                    if (this.current_file != null)
                        this.place ();
                    old_w = this.mainwindow.get_allocated_width  ();
                    old_h = this.mainwindow.get_allocated_height ();
                }
                return;
            });
            
            /*moving the window by drag, fullscreen for dbl-click*/
            bool moving = false;
            this.canvas.button_press_event.connect ( (e) => {
                if (e.click_count > 1){
                    toggle_fullscreen ();
                    return true;
                }else{
                    moving = true;
                    return true;
                }
            });
            clutter.motion_notify_event.connect ( (e) => {
                if (moving && this.settings.move_window){
                    moving = false;
                    this.mainwindow.begin_move_drag (1, 
                        (int)e.x_root, (int)e.y_root, e.time);
                    return true;
                }
                return false;
            });
            this.canvas.button_release_event.connect ( (e) => {
                moving = false;
                return false;
            });
            
            /*DnD*/
            Gtk.TargetEntry uris = {"text/uri-list", 0, 0};
            Gtk.drag_dest_set (this.mainwindow, 
                Gtk.DestDefaults.ALL, {uris}, Gdk.DragAction.MOVE);
            this.mainwindow.drag_data_received.connect ( (ctx, x, y, sel, info, time) => {
                for (var i=0;i<sel.get_uris ().length; i++)
                    this.playlist.add_item (File.new_for_uri (sel.get_uris ()[i]));
                this.open_file (sel.get_uris ()[0]);
                welcome.hide ();
                clutter.show_all ();
            });
            
            //save position in video when not finished playing
            this.mainwindow.destroy.connect ( () => {
                if (!reached_end){
                    for (var i=0;i<this.last_played_videos.length ();i+=2){
                        if (this.current_file.get_uri () == this.last_played_videos.nth_data (i)){
                            this.last_played_videos.nth (i+1).data = this.canvas.progress.to_string ();
                            this.save_last_played_videos ();
                            return;
                        }
                    }
                    //not in list yet, insert at start
                    this.last_played_videos.insert (this.current_file.get_uri (), 0);
                    this.last_played_videos.insert (this.canvas.progress.to_string (), 1);
                    if (this.last_played_videos.length () > 10){
                        this.last_played_videos.delete_link (this.last_played_videos.nth (10));
                        this.last_played_videos.delete_link (this.last_played_videos.nth (11));
                    }
                    this.save_last_played_videos ();
                }
            });
        }
        
        private inline void save_last_played_videos (){
            string res = "";
            for (var i=0;i<this.last_played_videos.length () - 1;i++){
                res += this.last_played_videos.nth_data (i) + ",";
            }
            res += this.last_played_videos.nth_data (this.last_played_videos.length () - 1);
            this.settings.last_played_videos = res;
        }
        
        public void run_open (int type){ //0=file, 1=cd, 2=dvd
            if (type == 0){
                var file = new Gtk.FileChooserDialog (_("Open"), this.mainwindow, Gtk.FileChooserAction.OPEN,
                    Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                    Gtk.Stock.OPEN, Gtk.ResponseType.ACCEPT);
                file.select_multiple = true;
                
                var all_files_filter = new Gtk.FileFilter ();
                all_files_filter.set_filter_name (_("All files"));
                all_files_filter.add_pattern ("*");
                
                var supported_filter = new Gtk.FileFilter ();
                supported_filter.set_filter_name (_("Supported files"));
                supported_filter.add_mime_type ("video/*");
                supported_filter.add_mime_type ("audio/*");
                
                var video_filter = new Gtk.FileFilter ();
                video_filter.set_filter_name (_("Video files"));
                video_filter.add_mime_type ("video/*");
                video_filter.add_pattern ("*.ogg");
                
                var audio_filter = new Gtk.FileFilter ();
                audio_filter.set_filter_name (_("Audio files"));
                audio_filter.add_mime_type ("audio/*");
                file.add_filter (all_files_filter);
                file.add_filter (supported_filter);
                file.add_filter (video_filter);
                file.add_filter (audio_filter);
                file.set_filter (supported_filter);
                
                file.set_current_folder (this.settings.last_folder);
                if (file.run () == Gtk.ResponseType.ACCEPT){
                    for (var i=0;i<file.get_files ().length ();i++){
                        this.playlist.add_item (file.get_files ().nth_data (i));
                    }
                    open_file (file.get_uri ());
                    welcome.hide ();
                    clutter.show_all ();
                    this.settings.last_folder = file.get_current_folder ();
                }
                file.destroy ();
            }else if (type == 1){
                open_file ("cdda://");
                canvas.get_pipeline ().set_state (Gst.State.PLAYING);
            }else if (type == 2){
                open_file ("dvd://");
                canvas.get_pipeline ().set_state (Gst.State.PLAYING);
            }
        }
        
        private void toggle_play (bool start){
            if (!start){
                if (this.pause.parent == toolbar){
                    toolbar.remove (this.pause);
                    toolbar.insert (this.play, 0);
                    play.show_all ();
                }
                canvas.get_pipeline ().set_state (Gst.State.PAUSED);
                Source.remove (this.hiding_timer);
                this.set_screensaver (true);
                this.playing = false;
            }else{
                if (this.reached_end){
                    canvas.progress = 0.0;
                    this.reached_end = false;
                }
                canvas.get_pipeline ().set_state (Gst.State.PLAYING);
                if (this.play.parent == toolbar){
                    toolbar.remove (this.play);
                    toolbar.insert (this.pause, 0);
                    pause.show_all ();
                }
                this.place ();
                if (this.hiding_timer != 0)
                    Source.remove (this.hiding_timer);
                this.hiding_timer = GLib.Timeout.add (2000, () => {
                    this.mainwindow.get_window ().set_cursor (blank_cursor);
                    float y2 = this.stage.height;
                    this.bar.animate (Clutter.AnimationMode.EASE_OUT_QUAD, 1000, y:y2);
                    return false;
                });
                this.set_screensaver (false);
                this.playing = true;
            }
        }
        
        private void toggle_fullscreen (){
            if (fullscreened){
                this.mainwindow.unmaximize ();
                this.mainwindow.unfullscreen ();
                this.fullscreened = false;
                this.toolbar.remove (this.unfullscreen);
            }else{
                this.mainwindow.fullscreen ();
                this.toolbar.insert (this.unfullscreen, 5);
                this.unfullscreen.show_all ();
                this.fullscreened = true;
            }
        }
        
        internal void open_file (string filename){
            this.error = false; //reset error
            this.current_file = File.new_for_commandline_arg (filename);
            this.reached_end = false;
            var uri = this.current_file.get_uri ();
            canvas.uri = uri;
            canvas.audio_volume = 1.0;
            previewer.uri = uri;
            previewer.audio_volume = 0.0;
            
            this.mainwindow.title = get_title (uri);
            if (this.settings.show_details)
                tagview.get_tags (uri, true);
            
            play.sensitive = true;
            
            this.toggle_play (true);
            this.place (true);
            
            if (this.settings.resume_videos && !(get_extension (uri) in audio)){
                int i;
                for (i=0;i<this.last_played_videos.length () && i!=-1;i+=2){
                    if (this.current_file.get_uri () == this.last_played_videos.nth_data (i))
                        break;
                    if (i == this.last_played_videos.length () - 1)
                        i = -1;
                }
                if (i != -1){
                    this.canvas.progress = double.parse (this.last_played_videos.nth_data (i + 1));
                    debug ("Resuming video from "+this.last_played_videos.nth_data (i + 1));
                }
            }
            
            Gtk.RecentManager recent_manager = Gtk.RecentManager.get_default ();
            recent_manager.add_item (uri);
        }
        
        private void place (bool resize_window = false){
            this.tagview.height   = stage.height;
            this.tagview.x        = (this.tagview.expanded)?stage.width-this.tagview.width:stage.width;
            
            var tb_height = 56;
            this.bar.width  = stage.width;
            this.bar.y      = stage.height - tb_height;
            this.bar.height = tb_height;
            this.bar.x      = 0;
            toolbar.width_request = (int)this.bar.width;
            toolbar.height_request = tb_height;
            
            canvas.get_base_size (out video_w, out video_h);
            //aspect ratio handling
            if (!this.error){
                if (stage.width < stage.height){
                    this.canvas.height = stage.height;
                    this.canvas.width  = stage.height / video_h * video_w;
                    this.canvas.x      = (stage.width - this.canvas.width) / 2.0f;
                    this.canvas.y      = 0.0f;
                }else{
                    this.canvas.width  = stage.width;
                    this.canvas.height = stage.width / video_w *  video_h;
                    this.canvas.y      = (stage.height - this.canvas.height) / 2.0f;
                    this.canvas.x      = 0.0f;
                }
                if (video_h < 30){ //video wasn't loaded fast enough, repeat untill it is
                    Timeout.add (100, () => {
                        this.place ();
                        if (video_h < 30){
                            return true;
                        }
                        if (resize_window)
                            fit_window ();
                        return false;
                    });
                }else if (resize_window){
                    fit_window ();
                }
            }
        }
        private void fit_window (){
            var ung = Gdk.Geometry (); /*unlock*/
            ung.min_aspect = 0.0;
            ung.max_aspect = 99999999.0;
            this.mainwindow.set_geometry_hints (this.mainwindow, ung, Gdk.WindowHints.ASPECT);
            
            if (Gdk.Screen.get_default ().width ()  > this.video_w &&
                Gdk.Screen.get_default ().height () > this.video_h){
                this.mainwindow.resize (
                    (int)this.video_w, (int)this.video_h);
            }else{
                this.mainwindow.resize (
                    (int)(Gdk.Screen.get_default ().width () * 0.9),
                    (int)(Gdk.Screen.get_default ().height () * 0.9));
            }
            
            if (this.settings.keep_aspect){
                var g = Gdk.Geometry (); /*lock*/
                g.min_aspect = g.max_aspect = this.video_w / this.video_h;
                this.mainwindow.set_geometry_hints (this.mainwindow, g, Gdk.WindowHints.ASPECT);
            }
        }
        
        public void set_screensaver (bool enable){
            var xid = (ulong)Gdk.X11Window.get_xid (mainwindow.get_window ());
            try{
                if (enable){
                    Process.spawn_command_line_sync (
                        "xdg-screensaver resume "+xid.to_string ());
                }else{
                    Process.spawn_command_line_sync (
                        "xdg-screensaver suspend "+xid.to_string ());
                }
            }catch (Error e){warning (e.message);}
        }
        
        //the application started
        public override void activate (){
            
        }
        
        //the application was requested to open some files
        public override void open (File [] files, string hint){
            for (var i=0;i<files.length;i++)
                this.playlist.add_item (files[i]);
            this.open_file (files[0].get_path ());
            this.welcome.hide ();
            this.clutter.show_all ();
        }
    }
}

public static void main (string [] args){
    var err = GtkClutter.init (ref args);
    if (err != Clutter.InitError.SUCCESS){
        error ("Could not initalize clutter! (a fallback will be available soon) "+err.to_string ());
    }
    ClutterGst.init (ref args);
    
    var app = new Audience.AudienceApp ();
    
    app.run (args);
}

