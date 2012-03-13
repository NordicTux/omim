#include "render_policy_st.hpp"

#include "../platform/platform.hpp"

#include "../yg/internal/opengl.hpp"

#include "queued_renderer.hpp"
#include "window_handle.hpp"
#include "render_queue.hpp"

RenderPolicyST::RenderPolicyST(VideoTimer * videoTimer,
                               bool useDefaultFB,
                               yg::ResourceManager::Params const & rmParams,
                               shared_ptr<yg::gl::RenderContext> const & primaryRC)
  : BasicRenderPolicy(primaryRC, false, 1, make_shared_ptr(new QueuedRenderer(1)))
{
  yg::ResourceManager::Params rmp = rmParams;

  rmp.selectTexRTFormat();

  rmp.m_primaryStoragesParams = yg::ResourceManager::StoragePoolParams(5000 * sizeof(yg::gl::Vertex),
                                                                       sizeof(yg::gl::Vertex),
                                                                       10000 * sizeof(unsigned short),
                                                                       sizeof(unsigned short),
                                                                       4,
                                                                       true,
                                                                       false,
                                                                       2,
                                                                       "primaryStorage",
                                                                       false,
                                                                       false);

  rmp.m_smallStoragesParams = yg::ResourceManager::StoragePoolParams(2000 * sizeof(yg::gl::Vertex),
                                                                     sizeof(yg::gl::Vertex),
                                                                     4000 * sizeof(unsigned short),
                                                                     sizeof(unsigned short),
                                                                     4,
                                                                     true,
                                                                     false,
                                                                     1,
                                                                     "smallStorage",
                                                                     false,
                                                                     false);

  rmp.m_blitStoragesParams = yg::ResourceManager::StoragePoolParams(10 * sizeof(yg::gl::Vertex),
                                                                    sizeof(yg::gl::Vertex),
                                                                    10 * sizeof(unsigned short),
                                                                    sizeof(unsigned short),
                                                                    50,
                                                                    true,
                                                                    true,
                                                                    1,
                                                                    "blitStorage",
                                                                    false,
                                                                    false);

  rmp.m_guiThreadStoragesParams = yg::ResourceManager::StoragePoolParams(300 * sizeof(yg::gl::Vertex),
                                                                         sizeof(yg::gl::Vertex),
                                                                         600 * sizeof(unsigned short),
                                                                         sizeof(unsigned short),
                                                                         20,
                                                                         true,
                                                                         true,
                                                                         1,
                                                                         "guiThreadStorage",
                                                                         false,
                                                                         false);

  rmp.m_primaryTexturesParams = yg::ResourceManager::TexturePoolParams(512,
                                                                       256,
                                                                       6,
                                                                       rmp.m_texFormat,
                                                                       true,
                                                                       true,
                                                                       true,
                                                                       1,
                                                                       "primaryTexture",
                                                                       false,
                                                                       false);

  rmp.m_fontTexturesParams = yg::ResourceManager::TexturePoolParams(512,
                                                                    256,
                                                                    6,
                                                                    rmp.m_texFormat,
                                                                    true,
                                                                    true,
                                                                    true,
                                                                    1,
                                                                    "fontTextures",
                                                                    false,
                                                                    false);

  rmp.m_guiThreadTexturesParams = yg::ResourceManager::TexturePoolParams(256,
                                                                         128,
                                                                         4,
                                                                         rmp.m_texFormat,
                                                                         true,
                                                                         true,
                                                                         true,
                                                                         1,
                                                                         "guiThreadTexture",
                                                                         false,
                                                                         false);

  rmp.m_glyphCacheParams = yg::ResourceManager::GlyphCacheParams("unicode_blocks.txt",
                                                                 "fonts_whitelist.txt",
                                                                 "fonts_blacklist.txt",
                                                                 2 * 1024 * 1024,
                                                                 2,
                                                                 1);

  rmp.m_useSingleThreadedOGL = true;
  rmp.m_useVA = !yg::gl::g_isBufferObjectsSupported;

  rmp.fitIntoLimits();

  m_resourceManager.reset();
  m_resourceManager.reset(new yg::ResourceManager(rmp));

  Platform::FilesList fonts;
  GetPlatform().GetFontNames(fonts);
  m_resourceManager->addFonts(fonts);

  DrawerYG::params_t p;

  p.m_frameBuffer = make_shared_ptr(new yg::gl::FrameBuffer(useDefaultFB));
  p.m_resourceManager = m_resourceManager;
  p.m_dynamicPagesCount = 2;
  p.m_textPagesCount = 2;
  p.m_glyphCacheID = m_resourceManager->guiThreadGlyphCacheID();
  p.m_skinName = GetPlatform().SkinName();
  p.m_visualScale = GetPlatform().VisualScale();
  p.m_isSynchronized = false;
  p.m_useGuiResources = true;

  m_drawer.reset();
  m_drawer.reset(new DrawerYG(p));

  m_windowHandle.reset();
  m_windowHandle.reset(new WindowHandle());

  m_windowHandle->setUpdatesEnabled(false);
  m_windowHandle->setRenderPolicy(this);
  m_windowHandle->setVideoTimer(videoTimer);
  m_windowHandle->setRenderContext(primaryRC);

  m_RenderQueue.reset();
  m_RenderQueue.reset(new RenderQueue(GetPlatform().SkinName(),
                false,
                false,
                0.1,
                false,
                GetPlatform().ScaleEtalonSize(),
                GetPlatform().VisualScale(),
                m_bgColor));

  m_RenderQueue->AddWindowHandle(m_windowHandle);

  m_RenderQueue->SetGLQueue(m_QueuedRenderer->GetPacketsQueue(0));
}

RenderPolicyST::~RenderPolicyST()
{
  LOG(LINFO, ("destroying RenderPolicyST"));

  m_QueuedRenderer->CancelQueuedCommands(0);

  LOG(LINFO, ("shutting down renderQueue"));

  m_RenderQueue.reset();

  LOG(LINFO, ("PartialRenderPolicy destroyed"));
}
