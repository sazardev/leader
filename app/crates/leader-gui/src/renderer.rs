//! The GPU side: one pipeline, one instance buffer, one glyph atlas, one draw call per frame.
//! Frames are only drawn when Neovim flushes or the window changes (no render loop).
use std::sync::Arc;

use leader_nvim::Screen;
use winit::window::Window;

use crate::font::Fonts;
use crate::scene::{self, Glyphs, Quad, View};

const ATLAS_START: u32 = 1024;

pub struct Renderer {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    pipeline: wgpu::RenderPipeline,
    layout: wgpu::BindGroupLayout,
    bind_group: wgpu::BindGroup,
    globals: wgpu::Buffer,
    atlas: wgpu::Texture,
    instances: wgpu::Buffer,
    capacity: usize,
    quads: Vec<Quad>,
    pub glyphs: Glyphs,
    linear: bool,
    max_texture: u32,
    timing: bool,
    pub adapter_info: String,
}

fn atlas_texture(device: &wgpu::Device, size: u32) -> wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label: Some("atlas"),
        size: wgpu::Extent3d { width: size, height: size, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    })
}

fn instance_buffer(device: &wgpu::Device, capacity: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("quads"),
        size: (capacity * size_of::<Quad>()) as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    })
}

impl Renderer {
    pub fn new(window: Arc<Window>, backends: wgpu::Backends) -> Result<Renderer, String> {
        let size = window.inner_size();
        let mut desc = wgpu::InstanceDescriptor::new_with_display_handle(Box::new(window.clone()));
        desc.backends = backends;
        let instance = wgpu::Instance::new(desc);
        let surface = instance.create_surface(window).map_err(|e| e.to_string())?;
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            compatible_surface: Some(&surface),
            ..Default::default()
        }))
        .map_err(|e| e.to_string())?;
        let info = adapter.get_info();
        let mut adapter_info = format!("{} ({:?})", info.name, info.backend);
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("leader"),
            required_limits: wgpu::Limits::downlevel_webgl2_defaults().using_resolution(adapter.limits()),
            memory_hints: wgpu::MemoryHints::Performance,
            ..Default::default()
        }))
        .map_err(|e| e.to_string())?;

        let caps = surface.get_capabilities(&adapter);
        let mut config =
            surface.get_default_config(&adapter, size.width.max(1), size.height.max(1)).ok_or("surface not supported by the adapter")?;
        // Terminal-exact colors: blend in sRGB space on a non-sRGB surface when there is one.
        config.format = caps.formats.iter().copied().find(|f| !f.is_srgb()).unwrap_or(caps.formats[0]);
        let linear = config.format.is_srgb();
        config.present_mode = [wgpu::PresentMode::Mailbox, wgpu::PresentMode::Fifo]
            .into_iter()
            .find(|m| caps.present_modes.contains(m))
            .unwrap_or(caps.present_modes[0]);
        config.alpha_mode = caps.alpha_modes[0];
        // Lowest latency: never queue more than one frame.
        config.desired_maximum_frame_latency = 1;
        surface.configure(&device, &config);
        adapter_info.push_str(&format!(", {:?}, {:?} of {:?}", config.format, config.present_mode, caps.present_modes));

        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("leader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shader.wgsl").into()),
        });
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("globals"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: false },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
            ],
        });
        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("leader"),
            bind_group_layouts: &[Some(&layout)],
            immediate_size: 0,
        });
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("quads"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs"),
                compilation_options: Default::default(),
                buffers: &[Some(wgpu::VertexBufferLayout {
                    array_stride: size_of::<Quad>() as u64,
                    step_mode: wgpu::VertexStepMode::Instance,
                    attributes: &wgpu::vertex_attr_array![0 => Float32x2, 1 => Float32x2, 2 => Float32x2, 3 => Float32x4, 4 => Uint32],
                })],
            },
            primitive: wgpu::PrimitiveState { topology: wgpu::PrimitiveTopology::TriangleStrip, ..Default::default() },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs"),
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: config.format,
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            multiview_mask: None,
            cache: None,
        });

        let globals = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("globals"),
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let max_texture = device.limits().max_texture_dimension_2d;
        let atlas = atlas_texture(&device, ATLAS_START);
        let bind_group = Self::bind(&device, &layout, &globals, &atlas);
        let capacity = 16 * 1024;
        let instances = instance_buffer(&device, capacity);
        Ok(Renderer {
            surface,
            device,
            queue,
            config,
            pipeline,
            layout,
            bind_group,
            globals,
            atlas,
            instances,
            capacity,
            quads: Vec::with_capacity(capacity),
            glyphs: Glyphs::new(ATLAS_START),
            linear,
            max_texture,
            timing: std::env::var_os("LEADER_TIMING").is_some(),
            adapter_info,
        })
    }

    fn bind(device: &wgpu::Device, layout: &wgpu::BindGroupLayout, globals: &wgpu::Buffer, atlas: &wgpu::Texture) -> wgpu::BindGroup {
        let view = atlas.create_view(&wgpu::TextureViewDescriptor::default());
        device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("globals"),
            layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: globals.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&view) },
            ],
        })
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        if width == 0 || height == 0 || (width == self.config.width && height == self.config.height) {
            return;
        }
        self.config.width = width;
        self.config.height = height;
        self.surface.configure(&self.device, &self.config);
    }

    /// Drops every cached glyph (font or size changed).
    pub fn clear_glyphs(&mut self) {
        let size = self.glyphs.size;
        self.glyphs.reset(size);
    }

    fn grow_atlas(&mut self) {
        let size = (self.glyphs.size * 2).min(self.max_texture);
        self.glyphs.reset(size);
        self.atlas = atlas_texture(&self.device, size);
        self.bind_group = Self::bind(&self.device, &self.layout, &self.globals, &self.atlas);
    }

    /// Builds the frame's quads and uploads them (and any new glyphs). Returns the quad count.
    fn prepare(&mut self, screen: &Screen, fonts: &mut Fonts, view: &View) -> u32 {
        let mut quads = std::mem::take(&mut self.quads);
        while scene::build(screen, fonts, &mut self.glyphs, view, &mut quads).is_err() {
            if self.glyphs.size >= self.max_texture {
                // Even the biggest atlas is full: start it over for this frame's glyphs only.
                self.clear_glyphs();
                if scene::build(screen, fonts, &mut self.glyphs, view, &mut quads).is_err() {
                    quads.clear();
                }
                break;
            }
            self.grow_atlas();
        }
        for up in self.glyphs.uploads.drain(..) {
            self.queue.write_texture(
                wgpu::TexelCopyTextureInfo {
                    texture: &self.atlas,
                    mip_level: 0,
                    origin: wgpu::Origin3d { x: up.x, y: up.y, z: 0 },
                    aspect: wgpu::TextureAspect::All,
                },
                &up.rgba,
                wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(up.width * 4), rows_per_image: Some(up.height) },
                wgpu::Extent3d { width: up.width, height: up.height, depth_or_array_layers: 1 },
            );
        }
        if quads.len() > self.capacity {
            self.capacity = quads.len().next_power_of_two();
            self.instances = instance_buffer(&self.device, self.capacity);
        }
        if !quads.is_empty() {
            self.queue.write_buffer(&self.instances, 0, bytemuck::cast_slice(&quads));
        }
        let globals = [self.config.width as f32, self.config.height as f32, if self.linear { 1.0 } else { 0.0 }, 0.0];
        self.queue.write_buffer(&self.globals, 0, bytemuck::cast_slice(&globals));
        let count = quads.len() as u32;
        self.quads = quads;
        count
    }

    /// Records the one render pass of a frame into `target`.
    fn encode(&self, screen: &Screen, count: u32, target: &wgpu::TextureView) -> wgpu::CommandEncoder {
        let bg = scene::rgb(screen.colors.bg, 1.0);
        let lin = |c: f32| if self.linear { if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) } } else { c };
        let clear = wgpu::Color { r: lin(bg[0]) as f64, g: lin(bg[1]) as f64, b: lin(bg[2]) as f64, a: 1.0 };
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("frame") });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("frame"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: target,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations { load: wgpu::LoadOp::Clear(clear), store: wgpu::StoreOp::Store },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            if count > 0 {
                pass.set_pipeline(&self.pipeline);
                pass.set_bind_group(0, &self.bind_group, &[]);
                pass.set_vertex_buffer(0, self.instances.slice(..));
                pass.draw(0..4, 0..count);
            }
        }
        encoder
    }

    pub fn render(&mut self, screen: &Screen, fonts: &mut Fonts, view: &View) {
        let t0 = std::time::Instant::now();
        let count = self.prepare(screen, fonts, view);
        let t_prepare = t0.elapsed();
        let frame = match self.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(f) | wgpu::CurrentSurfaceTexture::Suboptimal(f) => f,
            wgpu::CurrentSurfaceTexture::Outdated | wgpu::CurrentSurfaceTexture::Lost => {
                self.surface.configure(&self.device, &self.config);
                return;
            }
            _ => return,
        };
        let target = frame.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let encoder = self.encode(screen, count, &target);
        self.queue.submit([encoder.finish()]);
        self.queue.present(frame);
        if self.timing {
            eprintln!("[leader] frame: {count} quads, prepare {t_prepare:?}, total {:?}", t0.elapsed());
        }
    }

    /// Draws the frame offscreen and returns it as RGBA8 rows (for `LEADER_SNAPSHOT` and visual tests).
    pub fn snapshot(&mut self, screen: &Screen, fonts: &mut Fonts, view: &View) -> (u32, u32, Vec<u8>) {
        let (w, h) = (self.config.width, self.config.height);
        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("snapshot"),
            size: wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: self.config.format,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let count = self.prepare(screen, fonts, view);
        let mut encoder = self.encode(screen, count, &texture.create_view(&wgpu::TextureViewDescriptor::default()));
        let row = (w * 4).div_ceil(256) * 256;
        let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("snapshot"),
            size: (row * h) as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo { texture: &texture, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
            wgpu::TexelCopyBufferInfo {
                buffer: &buffer,
                layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(row), rows_per_image: Some(h) },
            },
            wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
        );
        self.queue.submit([encoder.finish()]);
        let slice = buffer.slice(..);
        slice.map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::wait_indefinitely());
        let bgra = matches!(self.config.format, wgpu::TextureFormat::Bgra8Unorm | wgpu::TextureFormat::Bgra8UnormSrgb);
        let mut out = Vec::with_capacity((w * h * 4) as usize);
        if let Ok(data) = slice.get_mapped_range() {
            for y in 0..h as usize {
                for px in data[y * row as usize..y * row as usize + w as usize * 4].chunks(4) {
                    if bgra {
                        out.extend_from_slice(&[px[2], px[1], px[0], 255])
                    } else {
                        out.extend_from_slice(&[px[0], px[1], px[2], 255])
                    }
                }
            }
        }
        (w, h, out)
    }
}
